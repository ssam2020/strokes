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
from tkinter import Tk, filedialog, messagebox, Checkbutton, Entry, BooleanVar, Button, W, Frame, LEFT, Label
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
        self.color_vars = []
        self.color_btns = []
        self.start_entries = []  # New: store start limits
        self.end_entries = []    # New: store end limits
        self.sens_vars = []  # New: high sensitivity checkboxes
        
        # Create task controls
        for i, (task, default_val) in enumerate(TASKS.items()):
            var = BooleanVar(value=True)
            color_var = BooleanVar(value=False)
            sens_var = BooleanVar(value=False)  # New
            self.check_vars.append(var)
            self.color_vars.append(color_var)
            self.sens_vars.append(sens_var)  # New
            
            row_frame = Frame(self)
            row_frame.grid(row=i, column=0, columnspan=5, sticky=W)  # Increased columnspan
            
            # Existing controls
            Checkbutton(row_frame, text=task, variable=var).pack(side=LEFT)
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
            color_btn.config(bg="#FFFFFF")
            color_btn.selected_color = (255, 255, 255)
            self.color_btns.append(color_btn)
            
            # New: Sensitivity checkbox
            Checkbutton(row_frame, text="High Sens", variable=sens_var).pack(side=LEFT, padx=(10,0))
            
            # New: Start/End controls
            Label(row_frame, text="Start:").pack(side=LEFT, padx=(10,0))
            start_entry = Entry(row_frame, width=5)
            start_entry.pack(side=LEFT)
            self.start_entries.append(start_entry)
            
            Label(row_frame, text="End:").pack(side=LEFT, padx=(5,0))
            end_entry = Entry(row_frame, width=5)
            end_entry.pack(side=LEFT)
            self.end_entries.append(end_entry)
            
        # Buttons
        Button(self, text="Launch", command=self.launch).grid(row=len(TASKS), column=0)
        Button(self, text="Process", command=self.process_selected_tasks).grid(row=len(TASKS), column=1)
        
    def validate_percent(self, text):
        return text.isdigit() and 0 <= int(text) <= 100 or text == ""
        
    def launch(self):
        selected_tasks = []
        for (task, _), var, entry, start_entry, end_entry in zip(TASKS.items(), self.check_vars, self.entries, 
                                                                self.start_entries, self.end_entries):
            if var.get():
                try:
                    selected_tasks.append((task, int(entry.get()), int(start_entry.get()) if start_entry.get() else None, int(end_entry.get()) if end_entry.get() else None))
                except ValueError:
                    messagebox.showerror("Error", f"Invalid percentage or limits for {task}")
                    return
                    
        if not selected_tasks:
            messagebox.showwarning("Warning", "No tasks selected")
            return
            
        # Ask for folder once here
        target_folder = filedialog.askdirectory(title="Select Target Folder")
        if not target_folder:
            return
            
        # Run all selected tasks with the same folder
        for task_name, target_percent, start_limit, end_limit in selected_tasks:
            self.run_task(task_name, target_percent, target_folder, start_limit, end_limit)
            
    def run_task(self, task_name, target_percent, target_folder, start_limit, end_limit):
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
        for (task, _), var, start_entry, end_entry in zip(TASKS.items(), self.check_vars, 
                                                        self.start_entries, self.end_entries):
            if var.get():
                # Get and validate limits
                start = start_entry.get().strip()
                end = end_entry.get().strip()
                try:
                    start_limit = int(start) if start else None
                    end_limit = int(end) if end else None
                except ValueError:
                    messagebox.showerror("Error", f"Invalid number in limits for {task}")
                    return
                
                selected_tasks.append((task.split('.')[0], start_limit, end_limit))
                
        if not selected_tasks:
            messagebox.showwarning("Warning", "No tasks selected for processing")
            return
            
        target_folder = filedialog.askdirectory(title="Select Root Folder")
        if not target_folder:
            return
            
        for task_name, start_limit, end_limit in selected_tasks:
            self.process_task_images(task_name, target_folder, start_limit, end_limit)
            
    def process_task_images(self, task_name, root_folder, start_limit=None, end_limit=None):
        task_folder = os.path.join(root_folder, task_name)
        output_folder = os.path.join(task_folder, "processed")
        
        # Clear existing processed files
        if os.path.exists(output_folder):
            for filename in os.listdir(output_folder):
                file_path = os.path.join(output_folder, filename)
                try:
                    if os.path.isfile(file_path):
                        os.unlink(file_path)
                except Exception as e:
                    print(f"Error deleting {file_path}: {e}")
        else:
            os.makedirs(output_folder, exist_ok=True)
        
        try:
            # Get files with limits applied
            files = sorted([f for f in os.listdir(task_folder) 
                          if f.lower().endswith(('.png', '.jpg', '.jpeg'))],
                          key=lambda x: int(re.search(r'\d+', x).group()))
            
            # Apply start/end limits
            if start_limit:
                start_idx = max(0, start_limit - 1)  # Convert to 0-based index
                files = files[start_idx:]
            if end_limit:
                end_idx = min(len(files), end_limit)  # End is exclusive
                files = files[:end_idx]
            
            if not files:
                messagebox.showwarning("Warning", f"No images in range for {task_folder}")
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
            composite_image = None  # Stores final accumulated result
            prev_og = None  # Previous original image

            # Load all images first
            images = [cv2.imread(os.path.join(task_folder, f)) 
                    for f in files if f.lower().endswith(('.png', '.jpg', '.jpeg'))]
            
            # Get sensitivity setting
            high_sens = self.sens_vars[task_index].get()
            
            # Process differences between consecutive images
            for i in range(len(images) - 1):
                current_img = images[i]
                next_img = images[i+1]
                
                # Calculate difference between consecutive frames
                difference = cv2.absdiff(current_img, next_img)
                total_diff = np.sum(difference, axis=2)
                normalized_diff = total_diff.astype(np.float32) / 765.0
                
                # Exponential alpha mapping
                if high_sens:
                    frame_alpha = (normalized_diff * 255).astype(np.uint8)
                else:
                    # Map 5% → 50% alpha, 15% → 100% alpha
                    scaled_diff = normalized_diff / 0.15  # 15% = max
                    scaled_diff = np.minimum(scaled_diff, 1.0)
                    # Solve equation: (0.05/0.15)^x = 0.5
                    exponent = np.log(0.5) / np.log(0.3333)  # ≈ 0.6309
                    frame_alpha = (np.power(scaled_diff, exponent) * 255).astype(np.uint8)
                # Create frame with next image's content and calculated alpha
                next_bgra = cv2.cvtColor(next_img, cv2.COLOR_BGR2BGRA)
                next_bgra[:, :, 3] = frame_alpha

                # Blend with previous composite (new over old)
                if composite_image is not None:
                    bg_float = composite_image.astype(np.float32) / 255.0
                    fg_float = next_bgra.astype(np.float32) / 255.0
                    
                    out_alpha = fg_float[:, :, 3] + bg_float[:, :, 3] * (1 - fg_float[:, :, 3])
                    out_rgb = (
                        fg_float[:, :, :3] * fg_float[:, :, [3,3,3]] +
                        bg_float[:, :, :3] * bg_float[:, :, [3,3,3]] * (1 - fg_float[:, :, [3,3,3]])
                    ) / np.maximum(out_alpha[:, :, None], 1e-6)
                    
                    composite_image = np.clip(np.concatenate([
                        (out_rgb * 255).astype(np.uint8),
                        (out_alpha * 255).astype(np.uint8)[:, :, None]
                    ], axis=2), 0, 255)
                else:
                    # First composite is just the initial difference
                    composite_image = next_bgra.copy()

                # Save intermediate result
                cv2.imwrite(os.path.join(output_folder, f"processed_{i:04d}.png"), composite_image)

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

