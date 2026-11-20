# PawPals OpenAPI 3.1

`openapi.yaml` adalah machine-readable contract untuk PawPals API v1 dan berada di repository utama agar dipakai bersama implementasi Express/TypeScript.

## Baseline
- API Contract AC-01 s.d. AC-12: FINAL / FROZEN
- Final API Cross-Review: PASSED
- Base path: `/api/v1`
- Authentication: server-managed session via HttpOnly cookie
- Pagination: `page` + `limit` (default 20, max 100)
- Money: integer IDR

## Aturan penggunaan
1. Jangan menambah endpoint/business rule baru dari file OpenAPI tanpa review scope.
2. Endpoint implementation harus mengikuti path, HTTP method, authorization, response envelope, dan state rule di contract.
3. `GenericWritePayload` hanya dipakai pada beberapa endpoint yang contract-nya membekukan behavior tetapi tidak merinci setiap field payload. Narrow schema tersebut sebelum endpoint terkait diimplementasikan.
4. Private UUID yang tidak dimiliki/tidak diotorisasi mengikuti privacy-aware 404; admin authenticated tanpa permission memakai 403 `ADMIN_PERMISSION_REQUIRED`.
5. HTTP 204 tidak memiliki response body.

## VS Code
File YAML dapat dibuka langsung di VS Code. Untuk preview interaktif, extension OpenAPI/Swagger/Redocly dapat dipasang kemudian; extension bukan requirement runtime PawPals.
