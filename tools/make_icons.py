"""从 assets/logo.svg 重新生成 assets/icon.png 和 assets/icon.ico。

用法:  python tools/make_icons.py
依赖:  Windows + Edge（SVG 渲染）+ Pillow（pip install pillow）

注意: Chromium 有最小窗口宽度（约 500px），小窗口截图会错位，
      因此固定用 1024 窗口渲染，再 LANCZOS 缩到各尺寸。
"""
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SVG = ROOT / "assets" / "logo.svg"
EDGE = Path(r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe")

SIZES = [256, 128, 64, 48, 32, 24, 16]
RENDER = 1024


def render(size: int) -> Image.Image:
    with tempfile.TemporaryDirectory() as td:
        out = Path(td) / "shot.png"
        subprocess.run(
            [
                str(EDGE), "--headless=new", "--disable-gpu", "--no-first-run",
                "--no-default-browser-check", "--hide-scrollbars",
                "--force-device-scale-factor=1",
                f"--user-data-dir={Path(td) / 'profile'}",
                f"--screenshot={out}",
                f"--window-size={size},{size}",
                "--default-background-color=FFFFFFFF",
                SVG.as_uri(),
            ],
            check=True, capture_output=True,
        )
        return Image.open(out).convert("RGBA")


master = render(RENDER)

# 圆角蒙版：与 SVG 瓷砖一致的 rx=58（58/256 * 1024 = 232），圆角外透明
mask = Image.new("L", master.size, 0)
ImageDraw.Draw(mask).rounded_rectangle(
    [0, 0, RENDER - 1, RENDER - 1], radius=232, fill=255
)
master.putalpha(mask)

frames = {s: master.resize((s, s), Image.LANCZOS) for s in SIZES}
frames[256].save(ROOT / "assets" / "icon.png")

imgs = [frames[s] for s in sorted(SIZES, reverse=True)]
# bitmap_format="bmp": 全部用传统 BMP 帧写入。
# FPC/LCL 的 FPImage 解析 ICO 时不支持 PNG 压缩帧（256px 帧默认会被
# PIL 写成 PNG），启动加载图标会报 "Bitmap with unknown compression"。
imgs[0].save(
    ROOT / "assets" / "icon.ico",
    append_images=imgs[1:],
    sizes=[(s, s) for s in SIZES],
    bitmap_format="bmp",
)

# 验证：所有帧必须是 BMP（无 PNG 魔数）
data = (ROOT / "assets" / "icon.ico").read_bytes()
count = int.from_bytes(data[4:6], "little")
ok = True
for i in range(count):
    off = int.from_bytes(data[6 + 16 * i + 12 : 6 + 16 * i + 16], "little")
    if data[off : off + 8] == b"\x89PNG\r\n\x1a\n":
        print(f"BAD: frame {i} is PNG-compressed")
        ok = False
if not ok:
    sys.exit(1)
print(f"OK: assets/icon.png, assets/icon.ico ({count} frames, all BMP)")
