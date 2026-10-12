# BoardBuddy — Recreation Plan

A full-stack platform that uses computer vision and ML to track a skateboarder's movement and deliver real-time, data-driven performance feedback.

> **2026-10-11 update:** Stage A (pose estimation) described below is
> superseded for the labeling workflow — pose extraction now runs natively
> on iOS via Google ML Kit (`apps/ios/`), not MediaPipe/TF.js. The rest of
> this plan (board detection, trick classification, scoring, dataset
> strategy) still applies; it just now consumes `ClipMetadata`/`PoseFrame`
> JSON from the iOS app instead of MediaPipe DataFrames. See
> [`apps/ios/README.md`](../apps/ios/README.md) for the new data model.

---

## 1. Platform recommendation: **start web-first, then wrap to mobile**

You asked for a trade-off pass before committing. Here's the honest version.

**Why web first**

- The whole ML/CV stack you need (MediaPipe Pose, MoveNet, BlazePose) runs in the browser via TensorFlow.js with near-native speed. No app store, no native build chain, no provisioning profiles.
- You can iterate on the model and the UX in the same `npm run dev` loop. That cuts your feedback cycle from minutes to seconds, which matters a lot when you're tuning a CV pipeline.
- A modern phone's browser can already hit 25–30 FPS on MoveNet Lightning. That's enough for live skating feedback. The remaining gap to "true mobile" is mostly camera UX and offline storage — both solvable.
- Recruiters reading your bullet ("full-stack mobile/web platform") see the deployed URL and play with it in 10 seconds. A mobile-only app means an APK or TestFlight invite, which most readers skip.

**Why not mobile-first**

- React Native + TFLite is doable but you'll spend 2–3 weeks on tooling (Metro bundler quirks, JSI bindings, model conversion, iOS code signing) before you write a single line of skating-related code.
- A native iOS app with CoreML is the fastest *runtime*, but the slowest *dev loop*, and you said the goal is to recreate something that worked — so optimize for getting back to "working" quickly.

**The migration path to mobile, when you want it**

1. Ship the web app as a **PWA** (installable, camera access, offline-capable). For ~80% of users this *is* the mobile app.
2. If you want true native later, wrap the same React frontend in **Capacitor** or **Expo** — same code, native shell. Your ML inference either stays in JS (TF.js) or swaps to TFLite via a native module.

**Bottom line:** Build a web app that behaves like a mobile app (responsive, portrait-first, camera-centric, PWA-installable). Call it a "full-stack mobile/web platform" honestly. Don't fragment your effort across two codebases for the recreation.

---

## 2. System architecture

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
│                               │                                 │
│                               ▼                                 │
│                       ┌───────────────┐                         │
│                       │ Trick classifier│  (lightweight, on-device│
│                       │ (TFLite/ONNX) │   for low-latency hints)│
│                       └───────┬───────┘                         │
└───────────────────────────────┼─────────────────────────────────┘
                                │ HTTPS (sessions, clips, metrics)
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Backend (FastAPI)                          │
│                                                                 │
│   ┌──────────────┐  ┌──────────────┐  ┌────────────────────┐    │
│   │ /sessions    │  │ /analyze     │  │ /train (admin)     │    │
│   │ CRUD + auth  │  │ heavy CV +   │  │ kicks off PyTorch  │    │
│   │              │  │ trick scoring│  │ training jobs      │    │
│   └──────┬───────┘  └──────┬───────┘  └─────────┬──────────┘    │
└──────────┼─────────────────┼────────────────────┼───────────────┘
           ▼                 ▼                    ▼
    ┌───────────┐     ┌──────────────┐    ┌──────────────────┐
    │ Postgres  │     │ S3 / R2      │    │ PyTorch training │
    │ (users,   │     │ (video clips,│    │ (Colab / Modal / │
    │ sessions, │     │ pose data)   │    │ your GPU)        │
    │ tricks)   │     │              │    │                  │
    └───────────┘     └──────────────┘    └──────────────────┘
```

**Two tiers of inference on purpose:**

- **On-device (TF.js)** — pose keypoints every frame, instant trick hints, real-time visual overlay. Latency budget: < 50 ms per frame.
- **Server-side (PyTorch)** — heavier analysis after a clip is captured: precise trick classification, scoring (rotation degrees, air time, board angle), comparisons against pro reference clips. Latency budget: a few seconds per clip is fine.

This split is what lets you say "real-time feedback" honestly while still having a meaningful PyTorch story for the resume.

**Stack picks**

| Layer            | Choice                          | Why                                                |
|------------------|---------------------------------|----------------------------------------------------|
| Frontend         | Next.js 14 (App Router) + TS    | SSR-capable, easy PWA, deploys to Vercel for free  |
| UI               | Tailwind + shadcn/ui            | Fast, professional-looking, customizable           |
| On-device ML     | TensorFlow.js + MoveNet Thunder | Real-time pose in the browser                      |
| Backend          | FastAPI (Python 3.11)           | Same language as your ML code; auto OpenAPI docs   |
| DB               | Postgres (Supabase or Neon)     | Free tier, hosted, easy auth bolt-on               |
| Object storage   | Cloudflare R2 or AWS S3         | Cheap clip storage; R2 has no egress fees          |
| Auth             | Supabase Auth or Clerk          | Don't build this yourself                          |
| Training         | PyTorch 2.x                     | Resume bullet says PyTorch — keep it for training  |
| Serving          | ONNX Runtime (server)           | Cleanly bridges PyTorch training → fast inference  |
| Deployment       | Vercel (frontend) + Fly.io/Render (API) | Both have generous free tiers              |

---

## 3. ML / CV pipeline

### Stage A — Pose estimation (the foundation)

Don't train your own pose model. Use a pretrained one. Your novel work is the layer on top.

- **MoveNet Lightning** (TF.js): 30+ FPS on phones, 17 keypoints, good for real-time overlay
- **MoveNet Thunder** (TF.js): slower but more accurate — use for "analyze" mode after capture
- **MediaPipe Pose** (also TF.js / Mediapipe Tasks): 33 keypoints incl. feet — better for stance/board tracking
- **YOLOv8-pose** (server-side PyTorch): top accuracy if you need it

**Recommendation:** MoveNet Lightning for live, MediaPipe Pose for server-side reanalysis. The extra foot keypoints from MediaPipe matter a lot for skateboarding.

### Stage B — Board detection

Skateboarding-specific layer. Two options:

1. **YOLOv8** fine-tuned on a small skateboard dataset (~500 labeled frames is enough to start). This gives you a bounding box + rotation per frame, which is huge for shuvit/flip detection.
2. **Hand-rolled heuristic** using the feet keypoints from MediaPipe — assume the board is between the feet, infer its angle from foot positions. Worse but free.

Start with option 2, upgrade to option 1 once you have a labeled dataset (you can label your own clips with Roboflow or CVAT).

### Stage C — Trick classification

This is your headline ML contribution. The recipe that works:

- **Input:** sequence of keypoint frames (e.g., 30 frames = 1 second at 30 FPS), each frame is a `(K, 2)` array of joint positions normalized to hip-center.
- **Model:** 1D-CNN over the temporal axis, or a small Transformer encoder, or LSTM. Start with **1D-CNN** — fastest to train, easiest to debug.
- **Output:** softmax over trick classes (`ollie`, `kickflip`, `heelflip`, `shuvit`, `pop_shuvit`, `none`).
- **Training:** PyTorch, trained on Colab/Kaggle GPU. 30 minutes per run once your dataset is set up.
- **Deployment:** export to **ONNX** → run server-side via `onnxruntime`, OR convert to **TFLite** → run on-device via TF.js.

### Stage D — Scoring & feedback

Rule-based on top of the trick classifier. Examples of metrics you can compute from keypoints + board box:

- **Air time:** frames between board-off-ground and board-back-on-ground / FPS
- **Rotation degrees:** integrate board angle change over the air-time window
- **Pop height:** max board-y-delta from baseline
- **Stance balance:** stddev of hip-x relative to mid-foot during approach
- **Knee bend:** angle at the knee joint during pop and landing

Each metric becomes a real-time HUD element and a per-session report.

### Dataset strategy (the part everyone underestimates)

You will not find a clean public skateboarding trick dataset. You'll have to make one. Plan:

1. **Bootstrap with YouTube** — download 50–100 trick clips per class, run pose extraction offline, label clip-level (no per-frame labels needed thanks to the sliding-window approach).
2. **Augment with your own footage** — phone on a tripod, you do tricks, label as you go.
3. **Augmentations:** horizontal flip (for regular/goofy stance), small rotations, time-warps. These double or triple your effective dataset for free.

Target: **30 clips per class minimum** for the first working classifier. You can hit that in a weekend of label-while-watching.

---

## 4. Phased recreation roadmap

### Milestone 0 — Skeleton (Day 1, ~3 hours)
- `pnpm create next-app@latest boardbuddy` with TS, Tailwind, App Router
- `poetry init` (or `uv init`) for the FastAPI backend in `apps/api`
- Set up a monorepo with `pnpm workspaces` or just two folders side by side
- "Hello world" page calling a `/health` endpoint — proves both halves run
- Push to GitHub, hook up Vercel for the frontend

**Exit criteria:** you can open the deployed URL and it pings your local API.

### Milestone 1 — Pose in the browser (Day 2–3)
- Add `@tensorflow/tfjs` + `@tensorflow-models/pose-detection`
- A page with camera permission, live video feed, MoveNet keypoints drawn on a `<canvas>` overlay
- A "record" button that captures 5 seconds of keypoint frames as JSON and downloads it
- Build a tiny labeling UI: load a JSON, mark which class it is, save back

**Exit criteria:** you can collect labeled clips of yourself doing tricks (or even mock tricks indoors) without touching another tool.

### Milestone 2 — First trick classifier (Day 4–6)
- Set up a Colab notebook (or a local Jupyter env) for PyTorch training
- Build the dataset loader from your labeled JSONs
- Train a 1D-CNN on 3 classes: `ollie`, `kickflip`, `none`. Aim for 70%+ validation accuracy on a tiny holdout
- Export to ONNX, run inference in your FastAPI `/analyze` endpoint
- Wire the frontend "record" flow to POST clips to `/analyze` and display the predicted class

**Exit criteria:** you upload (or record live) a clip and the app tells you what trick it was.

### Milestone 3 — Real-time HUD (Day 7–9)
- Compute the simple metrics (air time, knee bend) directly in the browser as keypoints stream in
- Build a HUD overlay: trick counter, current pose validity, "pop power" gauge
- Add session storage in Postgres — every recording creates a row with metrics
- A `/sessions` page that lists past sessions with a thumbnail and key metrics

**Exit criteria:** you can do 10 tricks in front of the camera and afterward see a summary of what you did.

### Milestone 4 — Server-side reanalysis (Day 10–12)
- Add MediaPipe Pose (Python) on the server for higher-accuracy reanalysis
- A "Deep analyze" button on each session that re-runs the heavier model and updates metrics
- Save the original clip to R2/S3 so reanalysis is possible without re-recording

**Exit criteria:** you can re-process a saved session with better models and see the metrics improve.

### Milestone 5 — Productionize + polish (Day 13–15)
- Auth (Supabase Auth)
- PWA manifest + service worker so it's installable on phones
- Mobile-friendly UI polish (portrait orientation lock, big touch targets, big record button)
- Public landing page explaining the project
- A 30-second demo video / GIF in the README

**Exit criteria:** you can hand a friend the URL, they install it on their phone, do a trick, and the app tells them what it was.

### Stretch goals (post-recreation)
- Multi-trick detection in a continuous video (sliding window + NMS in the temporal dimension)
- Pro-comparison: overlay a reference pro skater's keypoints next to yours and score similarity
- Coaching mode: pre-recorded drills with target metrics
- Native mobile via Capacitor wrap if/when you want it

---

## 5. Starter repo structure

```
boardbuddy/
├── apps/
│   ├── web/                    # Next.js frontend
│   │   ├── app/
│   │   │   ├── page.tsx        # Landing
│   │   │   ├── record/         # Camera + live pose
│   │   │   ├── sessions/       # History
│   │   │   └── api/health/     # Frontend health probe
│   │   ├── components/
│   │   │   ├── PoseCanvas.tsx  # MoveNet overlay
│   │   │   ├── HUD.tsx         # Live metrics
│   │   │   └── TrickBadge.tsx
│   │   ├── lib/
│   │   │   ├── pose.ts         # MoveNet wrapper
│   │   │   ├── metrics.ts      # Air time, knee angle, etc.
│   │   │   └── api.ts          # Backend client
│   │   └── public/
│   │       └── manifest.json   # PWA
│   │
│   └── api/                    # FastAPI backend
│       ├── boardbuddy/
│       │   ├── main.py         # App entry, routes
│       │   ├── routes/
│       │   │   ├── sessions.py
│       │   │   └── analyze.py
│       │   ├── ml/
│       │   │   ├── pose.py     # MediaPipe Pose wrapper
│       │   │   ├── classifier.py # ONNX runtime
│       │   │   └── metrics.py
│       │   ├── db/
│       │   │   └── models.py   # SQLModel / SQLAlchemy
│       │   └── storage.py      # S3/R2 client
│       └── pyproject.toml
│
├── ml/                         # Training pipeline (PyTorch)
│   ├── notebooks/
│   │   └── train_trick_classifier.ipynb
│   ├── boardbuddy_ml/
│   │   ├── data.py             # Dataset + augmentations
│   │   ├── model.py            # 1D-CNN architecture
│   │   ├── train.py            # CLI: python -m boardbuddy_ml.train
│   │   └── export.py           # PyTorch -> ONNX
│   └── data/
│       ├── raw_clips/          # gitignored
│       └── labels.jsonl
│
├── infra/
│   └── docker-compose.yml      # Postgres + MinIO for local dev
│
├── .github/workflows/          # CI: lint, typecheck, test, deploy
├── pnpm-workspace.yaml
└── README.md
```

### First five commands

```bash
# 1. Create the workspace
mkdir boardbuddy && cd boardbuddy
git init && pnpm init

# 2. Scaffold the frontend
pnpm create next-app@latest apps/web --typescript --tailwind --app --src-dir=false --import-alias="@/*"

# 3. Scaffold the backend
mkdir -p apps/api && cd apps/api
uv init --package boardbuddy
uv add fastapi uvicorn "pydantic[email]" sqlmodel python-multipart

# 4. Add the on-device ML libs (back in apps/web)
cd ../web
pnpm add @tensorflow/tfjs @tensorflow-models/pose-detection @mediapipe/tasks-vision

# 5. Boot the dev loop in two terminals
# terminal A:  cd apps/web && pnpm dev
# terminal B:  cd apps/api && uv run uvicorn boardbuddy.main:app --reload
```

---

## 6. Resume-bullet honesty check

Your original bullets are good but vague — anyone can write them. After the recreation, you'll be able to swap them for sharper, verifiable versions:

> **BoardBuddy** — Built a real-time skateboarding analytics PWA: MoveNet (TF.js) for in-browser pose tracking at 30 FPS, a PyTorch 1D-CNN trick classifier (90%+ accuracy across 5 trick classes on a self-collected 200-clip dataset), exported to ONNX for sub-100 ms server inference via FastAPI. Live at `boardbuddy.app`, code at `github.com/anthonytaboada/boardbuddy`.

Specific numbers + a live URL beat "architected a full-stack platform" every time.

---

## 7. What I need from you next

To make real progress, decide on these so the first commit makes sense:

1. **Trick classes for v1** — start with 3 (`ollie`, `kickflip`, `none`)? Or different?
2. **Hosting accounts** — do you already have Vercel / Supabase / Cloudflare? If not, we can use all free tiers.
3. **Where you want to start coding** — Milestone 0 (skeleton) or jump to Milestone 1 (browser pose) since you said you had a working prototype before?

Tell me which milestone you want to tackle first and I'll walk through it step by step with practice problems instead of just handing you code — your call on which mode you want.
