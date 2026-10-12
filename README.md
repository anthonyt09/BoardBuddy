# 🛹 BoardBuddy

> Real-time skateboarding analytics — pose tracking + trick classification in the browser, deeper analysis on the server.

BoardBuddy is a full-stack mobile/web PWA that uses computer vision and machine learning to track a skateboarder's movement and deliver real-time, data-driven performance feedback. Skate in front of any phone or laptop camera, and BoardBuddy tells you what trick you landed, how high you popped, your rotation, your stance balance, and where your form broke.

**Status:** active rebuild — recreating a previously-working prototype with a cleaner architecture.

> **2026-10-11 update:** pose extraction + trick labeling now happens in a
> native iOS app (`apps/ios/`) using Google ML Kit's on-device Pose
> Detection, replacing the `ml/boardbuddy_ml/pose.py` MediaPipe pipeline
> described below. See [`apps/ios/README.md`](apps/ios/README.md) for setup
> and the data model. The web/FastAPI architecture below is still accurate
> for everything else (sessions, deep server-side analysis); `ml/` is kept
> as reference for the training pipeline, not for pose extraction.

---

## Demo

_(Demo GIF / live URL go here once Milestone 1 ships.)_

---

## What it does

- **Live pose tracking** — MoveNet (TensorFlow.js) runs in the browser at ~30 FPS to extract 17 body keypoints per frame.
- **On-device trick hints** — a lightweight 1D-CNN trick classifier runs client-side via ONNX / TFLite for instant feedback.
- **Server-side deep analysis** — heavier reanalysis with MediaPipe Pose (33 keypoints incl. feet) and a full PyTorch classifier on FastAPI.
- **Performance metrics** — air time, pop height, rotation degrees, knee bend, stance balance, computed per trick.
- **Session history** — every recording is saved with thumbnails and metrics so you can compare progress over time.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Browser (Next.js PWA)                        │
│                                                                 │
│   ┌──────────────┐    ┌───────────────┐    ┌────────────────┐   │
│   │ Camera /     │───▶│ Pose model    │───▶│ Feedback UI    │   │
│   │ video upload │    │ (TF.js)       │    │ (overlay + HUD)│   │
│   └──────────────┘    └───────┬───────┘    └────────────────┘   │
│                               │                                 │
│                       keypoint stream                           │
│                               ▼                                 │
│                       ┌───────────────┐                         │
│                       │ Trick classifier│  (on-device, low-latency)
│                       │ (ONNX / TFLite)│                        │
│                       └───────┬───────┘                         │
└───────────────────────────────┼─────────────────────────────────┘
                                │ HTTPS (sessions, clips, metrics)
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Backend (FastAPI)                          │
│                                                                 │
│   /sessions  ·  /analyze (deep)  ·  /train (admin)              │
│      │              │                   │                       │
│      ▼              ▼                   ▼                       │
│   Postgres      S3 / R2 (clips)    PyTorch training             │
└─────────────────────────────────────────────────────────────────┘
```

---

## Tech stack

| Layer            | Choice                                |
|------------------|---------------------------------------|
| Frontend         | Next.js 14 (App Router) + TypeScript  |
| UI               | Tailwind CSS + shadcn/ui              |
| On-device ML     | TensorFlow.js + MoveNet               |
| Backend          | FastAPI (Python 3.11)                 |
| Database         | Postgres (Supabase / Neon)            |
| Object storage   | Cloudflare R2 (or AWS S3)             |
| Training         | PyTorch 2.x                           |
| Serving          | ONNX Runtime                          |
| Deployment       | Vercel (frontend) + Fly.io (API)      |

---

## Repo layout

```
boardbuddy/
├── apps/
│   ├── web/                # Next.js PWA frontend
│   └── api/                # FastAPI backend
├── ml/                     # PyTorch training pipeline + notebooks
├── infra/                  # docker-compose for local Postgres + MinIO
├── docs/                   # Architecture notes, decisions, plan
└── README.md
```

See [`docs/RECREATION_PLAN.md`](docs/RECREATION_PLAN.md) for the full architecture, ML pipeline, and milestone-by-milestone roadmap.

---

## Quickstart

> Requires Node 20+, Python 3.11+, and `pnpm` + `uv` installed.

```bash
# Clone
git clone https://github.com/anthonyt09/BoardBuddy.git
cd BoardBuddy

# Install JS deps
pnpm install

# Frontend (terminal A)
cd apps/web
pnpm dev
# → http://localhost:3000

# Backend (terminal B)
cd apps/api
uv sync
uv run uvicorn boardbuddy.main:app --reload
# → http://localhost:8000/health
```

---

## Roadmap

- [ ] **M0** — Repo skeleton, health check across web ↔ api
- [ ] **M1** — Live MoveNet pose overlay in the browser, capture labeled clips
- [ ] **M2** — First PyTorch trick classifier (ollie / kickflip / none), exported to ONNX
- [ ] **M3** — Real-time HUD with air time, pop height, knee bend
- [ ] **M4** — Server-side deep reanalysis with MediaPipe Pose
- [ ] **M5** — PWA install, auth, public landing page, demo video

Each milestone is tracked as a GitHub issue with sub-tasks.

---

## Why this project

Personal motivation: I skate, I'm a computer engineering student, and I wanted a project that pulls every part of the stack — ML, computer vision, real-time inference, mobile/web UX, backend systems, deployment — into one thing I actually use.

---

## License

MIT © Anthony Taboada
