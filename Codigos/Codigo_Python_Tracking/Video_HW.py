import re, glob
from pathlib import Path
import cv2

def natural_key(p):
    name = Path(p).name
    m = re.match(r"(\d+)", name)
    return int(m.group(1)) if m else 10**9

def make_mp4(frames_dir, out_mp4, fps=30):
    frames = sorted(glob.glob(str(Path(frames_dir) / "*.jpg")), key=natural_key)
    if not frames:
        raise RuntimeError(f"Nenhuma imagem .jpg encontrada em: {frames_dir}")

    first = cv2.imread(frames[0])
    if first is None:
        raise RuntimeError("Falha ao ler o primeiro frame.")

    h, w = first.shape[:2]
    fourcc = cv2.VideoWriter_fourcc(*"mp4v")
    vw = cv2.VideoWriter(str(out_mp4), fourcc, fps, (w, h))

    for f in frames:
        img = cv2.imread(f)
        if img is None:
            continue
        if img.shape[0] != h or img.shape[1] != w:
            img = cv2.resize(img, (w, h), interpolation=cv2.INTER_AREA)
        vw.write(img)

    vw.release()
    print("MP4 salvo em:", out_mp4)

# ============================================================
# CONFIG
# ============================================================
BASE = Path("/root/jupyter_notebooks/Tracking_Nathan_64_4")

RUNS = {
    ("scene1", "PSO"): BASE / "results_scene1_PSO" / "frames",
    ("scene1", "GWO"): BASE / "results_scene1_GWO" / "frames",
    ("scene2", "PSO"): BASE / "results_scene2_PSO" / "frames",
    ("scene2", "GWO"): BASE / "results_scene2_GWO" / "frames",
}

# Pasta única para TODOS os vídeos
VIDEO_OUT_DIR = BASE / "all_videos"
VIDEO_OUT_DIR.mkdir(parents=True, exist_ok=True)

VIDEO_FPS = 10  

# ============================================================
# EXEC
# ============================================================
for (scene, algo), frames_dir in RUNS.items():
    if not frames_dir.exists():
        print("PULANDO (frames_dir não existe):", frames_dir)
        continue

    out_mp4 = VIDEO_OUT_DIR / f"{scene}_{algo}.mp4"
    make_mp4(frames_dir, out_mp4, fps=VIDEO_FPS)

print("\nOK! Todos os vídeos salvos em:", VIDEO_OUT_DIR)
