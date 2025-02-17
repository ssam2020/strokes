# First run these commands in your terminal:
# pip install Pillow pyautogui

import os
import shutil
import pyautogui
import time
import re
from datetime import datetime
from PIL import ImageGrab
import pytesseract
from tkinter import Tk, filedialog, messagebox, Checkbutton, Entry, BooleanVar, Button, W, Frame, LEFT
import cv2
import numpy as np
from tkinter import colorchooser

# Configure Tesseract path
pyautogui.PAUSE = 0.2

# Configuration
TASKS = {
    "paint4.fsk": 60,
    "paint11.fsk": 60,
    "paint10.fsk": 40
}

class App(Tk):
    def __init__(self):
        super().__init__()
        self.title("Paint Automation")
        self.check_vars = []
        self.entries = []
        self.color_vars = []  # Store color checkboxes
        self.color_btns = []  # Store color buttons
        
        # Create task controls
        for i, (task, default_val) in enumerate(TASKS.items()):
            var = BooleanVar(value=True)
            color_var = BooleanVar(value=False)
            self.check_vars.append(var)
            self.color_vars.append(color_var)
            
            # Task row frame
            row_frame = Frame(self)
            row_frame.grid(row=i, column=0, columnspan=3, sticky=W)
            
            # Task checkbox + label
            Checkbutton(row_frame, text=task, variable=var).pack(side=LEFT)
            
            # Percentage entry
            entry = Entry(row_frame, width=5, validate='key',
                        vcmd=(self.register(self.validate_percent), '%P'))
            entry.insert(0, str(default_val))
            entry.pack(side=LEFT, padx=5)
            self.entries.append(entry)
            
            # Color controls
            Checkbutton(row_frame, variable=color_var).pack(side=LEFT, padx=(10,0))
            color_btn = Button(row_frame, text=" ", width=2, 
                             command=lambda t=task: self.choose_task_color(t))
            color_btn.pack(side=LEFT)
            color_btn.config(bg="#FFFFFF")  # Default white
            color_btn.selected_color = (255, 255, 255)
            self.color_btns.append(color_btn)
            
        # Buttons
        Button(self, text="Launch", command=self.launch).grid(row=len(TASKS), column=0)
        Button(self, text="Process", command=self.process_selected_tasks).grid(row=len(TASKS), column=1)
        
    def validate_percent(self, text):
        return text.isdigit() and 0 <= int(text) <= 100 or text == ""
        
    def launch(self):
        selected_tasks = []
        for (task, _), var, entry in zip(TASKS.items(), self.check_vars, self.entries):
            if var.get():
                try:
                    selected_tasks.append((task, int(entry.get())))
                except ValueError:
                    messagebox.showerror("Error", f"Invalid percentage for {task}")
                    return
                    
        if not selected_tasks:
            messagebox.showwarning("Warning", "No tasks selected")
            return
            
        # Ask for folder once here
        target_folder = filedialog.askdirectory(title="Select Target Folder")
        if not target_folder:
            return
            
        # Run all selected tasks with the same folder
        for task_name, percent in selected_tasks:
            self.run_task(task_name, percent, target_folder)
            
    def run_task(self, task_name, target_percent, target_folder):
        # Task-specific automation
        time.sleep(1)
        pyautogui.click(639,294)
        time.sleep(1)
        pyautogui.write(task_name)
        pyautogui.press('enter')
        pyautogui.click(1239, 645)
        
        # Get color for this task
        task_index = list(TASKS.keys()).index(task_name)
        if self.color_vars[task_index].get():
            dest_folder = os.path.join(target_folder, task_name.split('.')[0])
            base_color = self.color_btns[task_index].selected_color if hasattr(
                self.color_btns[task_index], 'selected_color') else (255, 255, 255)
            base_img = np.full((1080, 1920, 3), base_color[::-1], dtype=np.uint8)
            cv2.imwrite(os.path.join(dest_folder, "base_color.png"), base_img)
        
        while True:
            pyautogui.click(259, 47)
            time.sleep(0.2)
            
            if self.check_folder_percentage(target_folder, target_percent):
                pyautogui.press('esc', presses=2, interval=0.3)
                pyautogui.press('enter')
                self.move_processed_files(target_folder, task_name)
                break
            else:
                pyautogui.press('enter', presses=2, interval=0.3)
                time.sleep

    def check_folder_percentage(self, target_folder, target_percent):
        """Check selected folder for percentage files"""
        try:
            for file in os.listdir(target_folder):
                if "%" in file:
                    match = re.search(r'(\d+)%', file)
                    if match:
                        percent = int(match.group(1))
                        if percent >= target_percent:
                            return True
            return False
        except Exception as e:
            print(f"Folder error: {str(e)}")
            return False

    def move_processed_files(self, target_folder, task_name):
        """Move processed files to task-specific subfolder"""
        # Extract base name without extension (paint4, paint11, etc)
        folder_name = task_name.split('.')[0]
        dest_folder = os.path.join(target_folder, folder_name)
        
        # Clean/create destination folder
        if os.path.exists(dest_folder):
            for filename in os.listdir(dest_folder):
                file_path = os.path.join(dest_folder, filename)
                try:
                    if os.path.isfile(file_path):
                        os.unlink(file_path)
                except Exception as e:
                    print(f"Error deleting {file_path}: {e}")
        else:
            os.makedirs(dest_folder, exist_ok=True)
            
        # Move files
        moved_files = 0
        for filename in os.listdir(target_folder):
            if "fotosketcher" in filename.lower() and "%" in filename:
                src = os.path.join(target_folder, filename)
                dst = os.path.join(dest_folder, filename)
                shutil.move(src, dst)
                moved_files += 1
        print(f"Moved {moved_files} files to {dest_folder}")

    def process_selected_tasks(self):
        selected_tasks = []
        for (task, _), var in zip(TASKS.items(), self.check_vars):
            if var.get():
                selected_tasks.append(task.split('.')[0])
                
        if not selected_tasks:
            messagebox.showwarning("Warning", "No tasks selected for processing")
            return
            
        target_folder = filedialog.askdirectory(title="Select Root Folder")
        if not target_folder:
            return
            
        for task_name in selected_tasks:
            self.process_task_images(task_name, target_folder)
            
    def process_task_images(self, task_name, root_folder):
        task_folder = os.path.join(root_folder, task_name)
        output_folder = os.path.join(task_folder, "processed")
        os.makedirs(output_folder, exist_ok=True)
        
        try:
            # Get all image files sorted numerically
            files = sorted([f for f in os.listdir(task_folder) 
                          if f.lower().endswith(('.png', '.jpg', '.jpeg'))],
                          key=lambda x: int(re.search(r'\d+', x).group()))
            
            if not files:
                messagebox.showwarning("Warning", f"No images found in {task_folder}")
                return
                
            # Get task settings
            task_index = list(TASKS.keys()).index(task_name+".fsk")
            use_color = self.color_vars[task_index].get()
            base_color = self.color_btns[task_index].selected_color
            
            # Get reference dimensions
            first_img = cv2.imread(os.path.join(task_folder, files[0]))
            if first_img is None:
                messagebox.showerror("Error", f"Failed to read first image: {files[0]}")
                return
            ref_height, ref_width = first_img.shape[:2]
            
            # Create base image if enabled
            base_img = np.full((ref_height, ref_width, 3), base_color[::-1], dtype=np.uint8) if use_color else None
            prev_img = base_img
            
            for i, filename in enumerate(files):
                current_path = os.path.join(task_folder, filename)
                current_img = cv2.imread(current_path)
                if current_img is None:
                    messagebox.showerror("Error", f"Failed to read {filename}")
                    return
                    
                if prev_img is not None:
                    # Process difference
                    difference = cv2.absdiff(current_img, prev_img)
                    gray_diff = cv2.cvtColor(difference, cv2.COLOR_BGR2GRAY).astype(np.float32)
                    
                    # Normalize and create alpha mask
                    max_diff = np.max(gray_diff)
                    if max_diff > 0:
                        normalized_diff = gray_diff / max_diff
                        scaled_diff = np.minimum(normalized_diff * (4/3), 1.0)
                        exponent = np.log(0.05) / np.log(2/3)
                        alpha_mask = (np.power(scaled_diff, exponent) * 255).astype(np.uint8)
                    else:
                        alpha_mask = np.zeros_like(gray_diff, dtype=np.uint8)
                    
                    # Apply alpha channel and save as PNG
                    output_path = os.path.join(output_folder, f"processed_{i:04d}.png")
                    bgra = cv2.cvtColor(current_img, cv2.COLOR_BGR2BGRA)
                    bgra[:, :, 3] = alpha_mask
                    cv2.imwrite(output_path, bgra, [cv2.IMWRITE_PNG_COMPRESSION, 9])
                
                prev_img = current_img.copy()
                
            messagebox.showinfo("Success", f"Processed {len(files)} images in {task_name}")
            
        except Exception as e:
            messagebox.showerror("Error", f"Failed processing {task_name}: {str(e)}")

    def choose_task_color(self, task_name):
        color = colorchooser.askcolor(title=f"Color for {task_name}")[0]
        if color:
            task_index = list(TASKS.keys()).index(task_name)
            btn = self.color_btns[task_index]
            btn.config(bg=f"#{int(color[0]):02x}{int(color[1]):02x}{int(color[2]):02x}")
            btn.selected_color = tuple(int(c) for c in color)

def select_target_folder():
    """Open dialog to select monitoring folder"""
    root = Tk()
    root.withdraw()  # Hide main window
    folder = filedialog.askdirectory(title="Select Target Folder")
    root.destroy()
    return folder

def main():
    """Entry point with folder selection"""
    '''print("Starting automation - Please select target folder")
    target_folder = select_target_folder()
    
    if not target_folder:
        print("No folder selected. Exiting...")
        return
    
    print(f"Monitoring folder: {target_folder}")'''
    App().mainloop()
    print("Automation completed when target percentage was found!")

if __name__ == "__main__":
    main()

