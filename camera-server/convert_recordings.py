#!/usr/bin/env python3
"""
既存の録画ファイルをH.264形式に変換するスクリプト
"""

import subprocess
import os
from pathlib import Path
import sys
sys.path.append(str(Path(__file__).parent))
from main import generate_thumbnail, THUMBNAILS_DIR

def convert_video_to_h264(input_file, output_file):
    """動画ファイルをH.264形式に変換"""
    try:
        cmd = [
            'ffmpeg', '-i', str(input_file),
            '-c:v', 'libx264',
            '-preset', 'fast',
            '-crf', '23',
            '-y',  # 上書き
            str(output_file)
        ]
        
        result = subprocess.run(cmd, capture_output=True, text=True)
        
        if result.returncode == 0:
            print(f"変換成功: {input_file.name} -> {output_file.name}")
            return True
        else:
            print(f"変換失敗: {input_file.name}")
            print(f"エラー: {result.stderr}")
            return False
            
    except Exception as e:
        print(f"変換エラー: {e}")
        return False

def main():
    """メイン処理"""
    recordings_dir = Path("recordings")
    
    if not recordings_dir.exists():
        print("recordingsディレクトリが見つかりません")
        return
    
    # MP4ファイルを検索
    mp4_files = list(recordings_dir.glob("*.mp4"))
    
    if not mp4_files:
        print("変換対象のMP4ファイルが見つかりません")
        return
    
    print(f"変換対象ファイル数: {len(mp4_files)}")
    
    for mp4_file in mp4_files:
        print(f"処理中: {mp4_file.name}")
        
        # 一時ファイル名
        temp_file = mp4_file.with_suffix('.h264.mp4')
        
        # 変換実行
        if convert_video_to_h264(mp4_file, temp_file):
            # 元ファイルをバックアップ
            backup_file = mp4_file.with_suffix('.backup.mp4')
            mp4_file.rename(backup_file)
            
            # 変換済みファイルを元の名前に変更
            temp_file.rename(mp4_file)
            
            print(f"完了: {mp4_file.name}")
        else:
            print(f"スキップ: {mp4_file.name}")
    
    print("変換処理完了")

def generate_thumbnails_for_all_recordings():
    recordings_dir = Path("recordings")
    if not recordings_dir.exists():
        print("recordingsディレクトリが見つかりません")
        return
    mp4_files = list(recordings_dir.glob("*.mp4"))
    if not mp4_files:
        print("MP4ファイルが見つかりません")
        return
    print(f"サムネイル生成対象ファイル数: {len(mp4_files)}")
    for mp4_file in mp4_files:
        thumbnail_name = f"{mp4_file.stem}_thumb.jpg"
        thumbnail_path = THUMBNAILS_DIR / thumbnail_name
        print(f"サムネイル生成: {mp4_file.name} → {thumbnail_name}")
        if generate_thumbnail(mp4_file, thumbnail_path):
            print(f"  → 成功: {thumbnail_path}")
        else:
            print(f"  → 失敗: {thumbnail_path}")
    print("サムネイル生成処理完了")

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "thumb":
        generate_thumbnails_for_all_recordings()
    else:
        main() 