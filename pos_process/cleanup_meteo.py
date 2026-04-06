#!/usr/bin/python3
# -*- coding: UTF-8 -*-

import os
import sys
import argparse
import time
import shutil
from pathlib import Path

# Add local modules
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import utils as ut

def parse_args():
    parser = argparse.ArgumentParser(description="Cleanup old meteo files (wrfout, plots, data)")
    parser.add_argument("--dry-run", action="store_true", help="Print what would be deleted without actually deleting")
    parser.add_argument("--config", default=str(Path(__file__).parent.parent / "config.ini"), help="Path to config.ini")
    return parser.parse_args()

def get_file_age_days(filepath):
    """Return file age in days"""
    return (time.time() - os.path.getmtime(filepath)) / (24 * 3600)

def cleanup_directory(directory, days, dry_run=False, pattern="*"):
    """Recursively clean directory"""
    directory = Path(directory)
    if not directory.exists():
        print(f"Directory not found: {directory}")
        return 0, 0 # files, bytes

    print(f"Scanning {directory} for files older than {days} days...")
    
    count = 0
    size_freed = 0
    
    # Walk bottom-up so empty subdirectories can be safely deleted
    for root, dirs, files in os.walk(directory, topdown=False):
        for name in files:
            filepath = Path(root) / name
            
            # Simple check age
            try:
                age = get_file_age_days(filepath)
                if age > days:
                    size = os.path.getsize(filepath)
                    if dry_run:
                        print(f"[DRY-RUN] Would delete: {filepath} ({age:.1f} days old, {size/1024/1024:.2f} MB)")
                    else:
                        os.remove(filepath)
                        # print(f"Deleted: {filepath}")
                    
                    count += 1
                    size_freed += size
            except OSError as e:
                print(f"Error accessing {filepath}: {e}")

        # Attempt to remove directory if empty (skip the base directory itself)
        if Path(root) != directory:
            try:
                if not os.listdir(root):
                    if dry_run:
                        print(f"[DRY-RUN] Would delete empty directory: {root}")
                    else:
                        os.rmdir(root)
            except OSError as e:
                pass # Silently ignore directories that can't be read or removed

    return count, size_freed

def main():
    args = parse_args()
    
    print("=== Meteo Cleanup Tool ===")
    # Load paths using existing logic
    try:
        paths = ut.load_config_or_die(args.config, create_dirs=False)
        
        # Read cleanup_days explicitly from config.ini
        import configparser
        config = configparser.ConfigParser()
        config.read(args.config)
        
        if config.has_section('processing') and config.has_option('processing', 'cleanup_days'):
            days = config.getint('processing', 'cleanup_days')
        else:
            days = 3 # Default if missing
            
    except Exception as e:
        print(f"Failed to load config: {e}")
        sys.exit(1)
        
    print(f"Mode: {'DRY-RUN' if args.dry_run else 'DESTRUCTIVE'}")
    print(f"Threshold: > {days} days")

    targets = []
    
    # 1. WRF Output Files (in PROCESSED folder usually)
    # The config usually points wrfout_folder to the main dir, but processed files are moved to 'processed'
    if 'wrfout_folder' in paths:
        processed_dir = paths['wrfout_folder'] / 'processed'
        failed_dir = paths['wrfout_folder'] / 'failed'
        targets.append(processed_dir)
        targets.append(failed_dir)
    
    # 2. Plots
    if 'plots_folder' in paths:
        targets.append(paths['plots_folder'])
        
    # 3. Data (NetCDFs, etc)
    if 'data_folder' in paths:
        targets.append(paths['data_folder'])

    total_files = 0
    total_bytes = 0
    
    for target in targets:
        c, s = cleanup_directory(target, days, args.dry_run)
        total_files += c
        total_bytes += s
        
    print("==========================")
    print(f"Summary: {total_files} files {'would be' if args.dry_run else 'were'} deleted.")
    print(f"Space: {total_bytes / (1024*1024):.2f} MB {'reclaimable' if args.dry_run else 'reclaimed'}.")

if __name__ == "__main__":
    main()
