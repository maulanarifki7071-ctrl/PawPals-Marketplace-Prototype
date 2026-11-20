# PawPals Frontend

React 19 + Vite 8 + TypeScript SPA with Tailwind CSS 4, React Router and Lucide. It provides separate customer, vendor and admin experiences against the PawPals REST API.

## Development

Use Node.js 22.13+ within 22.x or Node.js 24. From this folder:

```powershell
npm ci
npm run lint
npm run build
npm run dev
```

Open http://localhost:5173. Run the backend, Redis/worker and local media emulator as described in the [root README](../README.md). Do not start a duplicate development server if the root startup script is already running.

| Command | Purpose |
|---|---|
| `npm run dev` | Vite development server |
| `npm run lint` | ESLint |
| `npm run build` | TypeScript project build and Vite production bundle |
| `npm run preview` | Preview built bundle (not production deployment) |

`vite.config.ts` proxies `/api` to `127.0.0.1:3000` and `/local-media` to `127.0.0.1:9100` in development. API requests use session cookies. Backend authorization remains authoritative; frontend route guards are not security boundaries.

## Source map

- `src/App.tsx`: application routes.
- `src/lib/api.ts`: API client and error handling.
- `src/`: pages, layout, shared components, state and styling.
- `public/photos/`: illustrative Premium UI/UX assets; not private customer uploads.

See [System Flow](../docs/system-flow/README.md) and [PRD](../docs/prd/README.md) for functional scope. Visual redesign is implemented; UX refinement and end-to-end verification remain ongoing.
