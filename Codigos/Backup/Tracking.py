from pynq import Overlay, allocate
import numpy as np
import cv2, time
from pathlib import Path
import matplotlib.pyplot as plt

# ============================================================
# 1) PATHS
# ============================================================
IMG_DIR1 = "/root/jupyter_notebooks/images"
IMG_DIR2 = "/root/jupyter_notebooks/images2"
GT1_PATH = "/root/jupyter_notebooks/GT.txt"
GT2_PATH = "/root/jupyter_notebooks/GT2.txt"
BIT_PATH = "/root/jupyter_notebooks/HOG_Nathan_32_2/hog.bit"

# ============================================================
# 2) HOG/HW CONFIG (hogpack)
# ============================================================
ROI_SIZE = 32
PADDING  = 1

# ============================================================
# 3) CONFIGS POR SCENE E POR ALGORITMO (VOCÊ AJUSTA AQUI)
# ============================================================
# Cada entrada pode ter:
# - pop: população/agentes
# - iters: iterações
# - search_r: raio de busca (pixels), dx,dy ∈ [-search_r, +search_r]
# - (PSO apenas) Vmax, wMax, wMin, c1, c2 (opcional)
#
CONFIG = {
    "scene1": {
        "PSO": {"pop": 40, "iters": 4, "search_r": 10, "Vmax": 4.0, "wMax": 0.9, "wMin": 0.2, "c1": 2.05, "c2": 2.05},
        "GWO": {"pop": 40, "iters": 4, "search_r": 10},
    },
    "scene2": {
        "PSO": {"pop": 50, "iters": 4, "search_r": 30, "Vmax": 4.0, "wMax": 0.9, "wMin": 0.2, "c1": 2.05, "c2": 2.05},
        "GWO": {"pop": 50, "iters": 4, "search_r": 30},
    }
}

# ============================================================
# 4) GT + FRAMES
# ============================================================
def load_gt_xywh(path):
    bbs = []
    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.replace(",", " ").split()
            if len(parts) < 4:
                raise ValueError(f"Formato GT inesperado: {line}")
            x, y, w, h = map(float, parts[:4])
            bbs.append((x, y, w, h))
    return bbs

def list_frames_seq(img_dir, nmax=60, ext=".jpg"):
    out = []
    for k in range(1, nmax + 1):
        p = Path(img_dir) / f"{k:03d}{ext}"
        if p.exists():
            out.append(str(p))
    return out

# ============================================================
# 5) GEOMETRIA / ROI / PADDING
# ============================================================
def bbox_center_xywh(b):
    x, y, w, h = b
    return (x + w/2.0, y + h/2.0)

def square_bbox_from_center(cx, cy, side):
    half = side / 2.0
    return (cx - half, cy - half, float(side), float(side))

def gt_to_roi_square_bbox(gt_xywh, roi_size=32):
    cx, cy = bbox_center_xywh(gt_xywh)
    return square_bbox_from_center(cx, cy, roi_size)

def crop_square_roi(img_gray, cx, cy, roi_size):
    H, W = img_gray.shape
    half = roi_size // 2
    x0 = int(round(cx)) - half
    y0 = int(round(cy)) - half

    roi = np.zeros((roi_size, roi_size), dtype=np.uint8)

    xs = max(0, x0)
    ys = max(0, y0)
    xe = min(W, x0 + roi_size)
    ye = min(H, y0 + roi_size)

    rx0 = xs - x0
    ry0 = ys - y0
    rx1 = rx0 + (xe - xs)
    ry1 = ry0 + (ye - ys)

    roi[ry0:ry1, rx0:rx1] = img_gray[ys:ye, xs:xe]
    return roi, x0, y0

def pad_zero(roi, padding):
    if padding <= 0:
        return roi
    return np.pad(roi, ((padding, padding), (padding, padding)),
                  mode="constant", constant_values=0)

def roi_to_inbuf(padded):
    return padded.reshape(-1).astype(np.uint8)

# ============================================================
# 6) MÉTRICAS
# ============================================================
def iou_xywh(a, b):
    ax, ay, aw, ah = a
    bx, by, bw, bh = b
    ax2, ay2 = ax + aw, ay + ah
    bx2, by2 = bx + bw, by + bh

    ix1, iy1 = max(ax, bx), max(ay, by)
    ix2, iy2 = min(ax2, bx2), min(ay2, by2)
    iw, ih = max(0.0, ix2 - ix1), max(0.0, iy2 - iy1)

    inter = iw * ih
    union = aw * ah + bw * bh - inter
    return 0.0 if union <= 0 else float(inter / union)

def cle_center(a, b):
    acx, acy = bbox_center_xywh(a)
    bcx, bcy = bbox_center_xywh(b)
    return float(((acx - bcx)**2 + (acy - bcy)**2) ** 0.5)

# ============================================================
# 7) STATS (sem pandas)
# ============================================================
def stats_summary(x):
    x = np.array(x, dtype=np.float64)
    mean = float(np.mean(x))
    median = float(np.median(x))
    var = float(np.var(x, ddof=1)) if x.size >= 2 else 0.0
    std = float(np.std(x, ddof=1)) if x.size >= 2 else 0.0
    return mean, median, var, std

def print_table_stats(title, ious, cles):
    i_mean, i_med, i_var, i_std = stats_summary(ious)
    c_mean, c_med, c_var, c_std = stats_summary(cles)

    print("\n" + "="*72)
    print(title)
    print("="*72)
    print(f"{'Métrica':<8} | {'Média':>10} | {'Mediana':>10} | {'Variância':>12} | {'Desv.Pad.':>10}")
    print("-"*72)
    print(f"{'IoU':<8} | {i_mean:10.6f} | {i_med:10.6f} | {i_var:12.6f} | {i_std:10.6f}")
    print(f"{'CLE':<8} | {c_mean:10.6f} | {c_med:10.6f} | {c_var:12.6f} | {c_std:10.6f}")
    print("-"*72)

# ============================================================
# 8) HOG HW runner
# ============================================================
ol = Overlay(BIT_PATH)
dma = ol.axi_dma_0
hog = ol.hog_ip_axi_Nathan_0

def rd(a): return hog.read(a)
def wr(a, v): hog.write(a, v)

TOTAL_PIXELS_IN = rd(0x10)
NUM_WORDS       = rd(0x14)
print("TOTAL_PIXELS_IN =", TOTAL_PIXELS_IN)
print("NUM_WORDS       =", NUM_WORDS)

PAD_SIZE = int(round(TOTAL_PIXELS_IN ** 0.5))
assert PAD_SIZE * PAD_SIZE == TOTAL_PIXELS_IN, "TOTAL_PIXELS_IN não é quadrado perfeito"
print("PAD_SIZE inferred =", PAD_SIZE)
assert PAD_SIZE == ROI_SIZE + 2 * PADDING, "PAD_SIZE não bate com ROI_SIZE+2*PADDING"

in_buf  = allocate(shape=(TOTAL_PIXELS_IN,), dtype=np.uint8)
out_buf = allocate(shape=(NUM_WORDS,), dtype=np.uint32)

def hog_hw(padded_img_u8):
    flat = roi_to_inbuf(padded_img_u8)
    if flat.size != TOTAL_PIXELS_IN:
        raise ValueError("Tamanho do input não bate com TOTAL_PIXELS_IN")
    in_buf[:] = flat
    out_buf[:] = 0

    wr(0x18, 0x1)  # clear
    wr(0x00, 0x1)  # start

    dma.recvchannel.transfer(out_buf)
    dma.sendchannel.transfer(in_buf)
    dma.sendchannel.wait()
    dma.recvchannel.wait()

    return np.array(out_buf, dtype=np.uint32)

# custo por BYTE (mais coerente com empacotamento)
def hog_cost(words, templ_words):
    a = words.view(np.uint8).astype(np.int16)
    b = templ_words.view(np.uint8).astype(np.int16)
    return int(np.sum(np.abs(a - b)))

# ============================================================
# 9) Objective function
# ============================================================
def make_objf_tracking(img_gray, templ_words, cx0, cy0):
    def objf(x):
        dx, dy = float(x[0]), float(x[1])
        cx = cx0 + dx
        cy = cy0 + dy
        roi, _, _ = crop_square_roi(img_gray, cx, cy, ROI_SIZE)
        pad = pad_zero(roi, PADDING)
        words = hog_hw(pad)
        return hog_cost(words, templ_words)
    objf.__name__ = "tracking_objf"
    return objf

# ============================================================
# 10) PSO / GWO (com configs)
# ============================================================
def PSO(objf, lb, ub, dim, PopSize, iters, Vmax=6.0, wMax=0.9, wMin=0.2, c1=2.0, c2=2.0):
    lb = np.array(lb, dtype=np.float64)
    ub = np.array(ub, dtype=np.float64)

    vel = np.zeros((PopSize, dim), dtype=np.float64)
    pBestScore = np.full(PopSize, np.inf, dtype=np.float64)
    pBest = np.zeros((PopSize, dim), dtype=np.float64)

    gBest = np.zeros(dim, dtype=np.float64)
    gBestScore = np.inf

    pos = np.random.uniform(0, 1, (PopSize, dim)) * (ub - lb) + lb
    pos[0, :] = 0.0  # sempre testa (0,0)

    for l in range(iters):
        for i in range(PopSize):
            pos[i, :] = np.clip(pos[i, :], lb, ub)
            fitness = objf(pos[i, :])

            if fitness < pBestScore[i]:
                pBestScore[i] = fitness
                pBest[i, :] = pos[i, :].copy()

            if fitness < gBestScore:
                gBestScore = fitness
                gBest = pos[i, :].copy()

        w = wMax - l * ((wMax - wMin) / max(1, iters))

        r1 = np.random.rand(PopSize, dim)
        r2 = np.random.rand(PopSize, dim)

        vel = (w * vel
               + c1 * r1 * (pBest - pos)
               + c2 * r2 * (gBest.reshape(1, -1) - pos))

        vel = np.clip(vel, -Vmax, Vmax)
        pos = pos + vel
        pos[0, :] = 0.0  # mantém (0,0) sempre presente

    return {
        "best": float(gBestScore),
        "bestIndividual": gBest.copy()
    }

def GWO(objf, lb, ub, dim, SearchAgents_no, Max_iter):
    lb = np.array(lb, dtype=np.float64)
    ub = np.array(ub, dtype=np.float64)

    Alpha_pos = np.zeros(dim, dtype=np.float64)
    Alpha_score = np.inf
    Beta_pos = np.zeros(dim, dtype=np.float64)
    Beta_score = np.inf
    Delta_pos = np.zeros(dim, dtype=np.float64)
    Delta_score = np.inf

    Positions = np.random.uniform(0, 1, (SearchAgents_no, dim)) * (ub - lb) + lb
    Positions[0, :] = 0.0  # sempre testa (0,0)

    for l in range(Max_iter):
        for i in range(SearchAgents_no):
            Positions[i, :] = np.clip(Positions[i, :], lb, ub)
            fitness = objf(Positions[i, :])

            if fitness < Alpha_score:
                Delta_score, Delta_pos = Beta_score, Beta_pos.copy()
                Beta_score, Beta_pos = Alpha_score, Alpha_pos.copy()
                Alpha_score, Alpha_pos = fitness, Positions[i, :].copy()
            elif fitness < Beta_score:
                Delta_score, Delta_pos = Beta_score, Beta_pos.copy()
                Beta_score, Beta_pos = fitness, Positions[i, :].copy()
            elif fitness < Delta_score:
                Delta_score, Delta_pos = fitness, Positions[i, :].copy()

        a = 2.0 - l * (2.0 / max(1, Max_iter))

        r1 = np.random.rand(SearchAgents_no, dim)
        r2 = np.random.rand(SearchAgents_no, dim)
        A1 = 2*a*r1 - a
        C1 = 2*r2
        D_alpha = np.abs(C1 * Alpha_pos.reshape(1, -1) - Positions)
        X1 = Alpha_pos.reshape(1, -1) - A1 * D_alpha

        r1 = np.random.rand(SearchAgents_no, dim)
        r2 = np.random.rand(SearchAgents_no, dim)
        A2 = 2*a*r1 - a
        C2 = 2*r2
        D_beta = np.abs(C2 * Beta_pos.reshape(1, -1) - Positions)
        X2 = Beta_pos.reshape(1, -1) - A2 * D_beta

        r1 = np.random.rand(SearchAgents_no, dim)
        r2 = np.random.rand(SearchAgents_no, dim)
        A3 = 2*a*r1 - a
        C3 = 2*r2
        D_delta = np.abs(C3 * Delta_pos.reshape(1, -1) - Positions)
        X3 = Delta_pos.reshape(1, -1) - A3 * D_delta

        Positions = (X1 + X2 + X3) / 3.0
        Positions[0, :] = 0.0  # mantém (0,0)

    return {
        "best": float(Alpha_score),
        "bestIndividual": Alpha_pos.copy()
    }

# ============================================================
# 11) Drawing + dirs
# ============================================================
def draw_boxes_and_save(img_bgr, gt_bbox, pred_bbox, out_path):
    x, y, w, h = gt_bbox
    px, py, pw, ph = pred_bbox
    img = img_bgr.copy()

    cv2.rectangle(img,
                  (int(round(x)), int(round(y))),
                  (int(round(x + w)), int(round(y + h))),
                  (255, 0, 0), 2)

    cv2.rectangle(img,
                  (int(round(px)), int(round(py))),
                  (int(round(px + pw)), int(round(py + ph))),
                  (0, 0, 255), 2)

    cv2.imwrite(str(out_path), img)

def ensure_dir(p):
    Path(p).mkdir(parents=True, exist_ok=True)

# ============================================================
# 12) Runner (usa CONFIG[scene][algo])
# ============================================================
def run_tracking_one(scene_name, algo_name, img_dir, gt_path, nframes=60):
    cfg = CONFIG[scene_name][algo_name]

    pop = int(cfg["pop"])
    iters = int(cfg["iters"])
    search_r = int(cfg["search_r"])

    frames = list_frames_seq(img_dir, nmax=nframes, ext=".jpg")
    gt_raw = load_gt_xywh(gt_path)
    N = min(nframes, len(frames), len(gt_raw))
    if N < 2:
        raise RuntimeError("Poucos frames/GT para rodar tracking.")

    gt_sq = [gt_to_roi_square_bbox(bb, ROI_SIZE) for bb in gt_raw[:N]]

    base_dir = Path(BIT_PATH).parent
    out_dir = base_dir / f"results_{scene_name}_{algo_name}"
    frames_dir = out_dir / "frames"
    ensure_dir(frames_dir)

    print(f"\n== {scene_name} | {algo_name} | N={N} | saving to: {out_dir} ==")
    print(f"   config: pop={pop}, iters={iters}, search_r={search_r}")

    # Frame 0 -> template
    img0 = cv2.imread(frames[0], cv2.IMREAD_GRAYSCALE)
    if img0 is None:
        raise RuntimeError(f"Falha ao ler {frames[0]}")
    gt0 = gt_sq[0]
    cx0, cy0 = bbox_center_xywh(gt0)

    roi0, _, _ = crop_square_roi(img0, cx0, cy0, ROI_SIZE)
    pad0 = pad_zero(roi0, PADDING)
    templ = hog_hw(pad0)

    # init estimate = GT center at frame 0
    cx_est, cy_est = cx0, cy0

    ious = []
    cles = []
    fps_each = []

    # save frame 0
    img0_bgr = cv2.imread(frames[0], cv2.IMREAD_COLOR)
    draw_boxes_and_save(img0_bgr, gt0, gt0, frames_dir / f"001_{algo_name}.jpg")
    ious.append(iou_xywh(gt0, gt0))
    cles.append(cle_center(gt0, gt0))
    fps_each.append(float("nan"))

    lb = [-search_r, -search_r]
    ub = [ search_r,  search_r]
    dim = 2

    for k in range(1, N):
        t_start = time.time()

        img = cv2.imread(frames[k], cv2.IMREAD_GRAYSCALE)
        if img is None:
            raise RuntimeError(f"Falha ao ler {frames[k]}")
        H, W = img.shape

        gt_k = gt_sq[k]
        objf = make_objf_tracking(img, templ, cx_est, cy_est)

        if algo_name == "PSO":
            # PSO params opcionais por config
            Vmax = float(cfg.get("Vmax", 6.0))
            wMax = float(cfg.get("wMax", 0.9))
            wMin = float(cfg.get("wMin", 0.2))
            c1   = float(cfg.get("c1", 2.0))
            c2   = float(cfg.get("c2", 2.0))

            sol = PSO(objf, lb, ub, dim, pop, iters, Vmax=Vmax, wMax=wMax, wMin=wMin, c1=c1, c2=c2)

        elif algo_name == "GWO":
            sol = GWO(objf, lb, ub, dim, pop, iters)

        else:
            raise ValueError("algo_name deve ser 'PSO' ou 'GWO'")

        dx_best, dy_best = sol["bestIndividual"]
        cx_est += float(dx_best)
        cy_est += float(dy_best)

        # clip no frame
        cx_est = float(np.clip(cx_est, 0, W - 1))
        cy_est = float(np.clip(cy_est, 0, H - 1))

        pred_bbox = square_bbox_from_center(cx_est, cy_est, ROI_SIZE)

        ious.append(iou_xywh(pred_bbox, gt_k))
        cles.append(cle_center(pred_bbox, gt_k))

        dt = time.time() - t_start
        fps_each.append(1.0 / dt if dt > 0 else 0.0)

        img_bgr = cv2.imread(frames[k], cv2.IMREAD_COLOR)
        draw_boxes_and_save(img_bgr, gt_k, pred_bbox, frames_dir / f"{k+1:03d}_{algo_name}.jpg")

    # plots
    frames_idx = np.arange(1, N + 1)

    plt.figure()
    plt.plot(frames_idx, ious)
    plt.xlabel("Frame (001..)")
    plt.ylabel("IoU")
    plt.title(f"IoU por frame - {scene_name} - {algo_name}")
    plt.grid(True)
    plt.savefig(out_dir / "iou_per_frame.png", dpi=150, bbox_inches="tight")
    plt.close()

    plt.figure()
    plt.plot(frames_idx, cles)
    plt.xlabel("Frame (001..)")
    plt.ylabel("CLE (px)")
    plt.title(f"CLE por frame - {scene_name} - {algo_name}")
    plt.grid(True)
    plt.savefig(out_dir / "cle_per_frame.png", dpi=150, bbox_inches="tight")
    plt.close()

    mean_fps = float(np.nanmean(fps_each[1:])) if N > 1 else 0.0
    print_table_stats(
        f"Resumo Estatístico | {scene_name} | {algo_name} | Mean FPS (frames 2..N): {mean_fps:.2f}",
        ious, cles
    )

    return {"scene": scene_name, "algo": algo_name, "out_dir": str(out_dir)}

def run_all(nframes=60):
    runs = []

    runs.append(run_tracking_one("scene1", "PSO", IMG_DIR1, GT1_PATH, nframes=nframes))
    runs.append(run_tracking_one("scene1", "GWO", IMG_DIR1, GT1_PATH, nframes=nframes))
    runs.append(run_tracking_one("scene2", "PSO", IMG_DIR2, GT2_PATH, nframes=nframes))
    runs.append(run_tracking_one("scene2", "GWO", IMG_DIR2, GT2_PATH, nframes=nframes))

    print("\n" + "="*72)
    print("Pastas geradas:")
    for r in runs:
        print(f"- {r['scene']} | {r['algo']} -> {r['out_dir']}")
    print("="*72)
    return runs

# =========================
# EXECUTE
# =========================
runs = run_all(nframes=60)
