# figma-roblox-mcp

A local **stdio** MCP server that reads Figma files and converts frames into **Roblox GUI (Luau)** code.

## Why this exists

Figma's official hosted MCP (`https://mcp.figma.com/mcp`) is **HTTP-only** and **refuses Dynamic Client Registration** — bridging it into a stdio-only client via `mcp-remote` dies with:

```
HTTP 403 ... Raw body: Forbidden   at registerClient
```

This server skips OAuth entirely: the **Figma REST API** authenticates with a plain
`X-Figma-Token` header, which works anywhere.

## Setup

1. **Get a token** — figma.com → **Settings → Security → Personal access tokens** →
   *Generate new token*. Scope: **File content → Read**. Copy it (shown once).
2. **Put it in the config** — in `claude_desktop_config.json`, replace
   `PUT_YOUR_FIGMA_TOKEN_HERE`:

```json
"figma-roblox": {
  "command": "node",
  "args": ["D:\\ui\\zaddz\\index.js"],
  "env": { "FIGMA_TOKEN": "figd_xxxxxxxxxxxxxxxx" }
}
```

3. **Fully quit and reopen Claude Desktop** (tray → Quit; config is read only at boot).

## Tools

| Tool | What it does |
|---|---|
| `figma_file_info` | File metadata + pages + top-level frames. **Start here.** |
| `figma_list_frames` | Every frame/component/group (3 levels) with id, page, pixel size. Supports `filter`. |
| `figma_get_node` | Inspect one node's structure without converting. |
| `figma_to_roblox` | **Main tool.** Frame → Roblox Luau GUI. Optional `outFile` to write the `.lua`. |
| `figma_export_image` | Rendered PNG/SVG URL for a node (icons, logos, image fills). |
| `figma_get_styles` | Published colour/text styles — for building a theme table. |

Every tool accepts a **raw file key or a full Figma URL**, and node ids in either
`1:23` or the URL's `node-id=1-23` form.

## What the converter maps

| Figma | Roblox |
|---|---|
| FRAME / GROUP / COMPONENT / INSTANCE / RECTANGLE / VECTOR | `Frame` |
| TEXT | `TextLabel` (text, size, colour, alignment, font) |
| absoluteBoundingBox | `UDim2.fromOffset` — child offset = child.absolute − parent.absolute |
| Solid fill | `BackgroundColor3` + `BackgroundTransparency` |
| Linear/radial gradient | base colour + `UIGradient` (`ColorSequence` + rotation from handles) |
| cornerRadius | `UICorner` |
| ELLIPSE | `UICorner` = `UDim.new(1, 0)` |
| strokes + strokeWeight | `UIStroke` (`ApplyStrokeMode.Border` when strokeAlign=INSIDE) |
| Auto-layout | `UIListLayout` (direction, padding, alignment) + `UIPadding` |
| clipsContent | `ClipsDescendants` |
| opacity | `Transparency` (inverted: Figma 1 = opaque, Roblox 0 = opaque) |
| fontFamily + fontWeight | closest `Enum.Font` (Inter/Roboto/Poppins → Gotham family) |

## Known limits

- **Image fills** can't auto-convert — Roblox needs an uploaded asset id. The converter
  emits a `-- TODO image fill` marker; use `figma_export_image`, upload, then swap in an
  `ImageLabel`.
- **UICorner is uniform** — Figma per-corner radii collapse to the max.
- **Drop shadows / blurs** aren't emitted (Roblox has no direct equivalent).
- Fonts are a **best-effort** map to Roblox's fixed `Enum.Font` set.
- `maxNodes` defaults to **400** to stop a huge file emitting thousands of instances.

## Usage

```
figma_list_frames  file="https://figma.com/design/abc123/MyUI"
figma_to_roblox    file="abc123" node="1:23" parentTo="gethui" outFile="D:\\ui\\zaddz\\out\\menu.lua"
```

`parentTo`: `PlayerGui` (default) · `CoreGui` · `gethui` (use this for exploit UIs —
keeps the GUI out of PlayerGui where anticheats scan).

## Dev

```bash
npm install
node index.js   # speaks MCP over stdio
```
