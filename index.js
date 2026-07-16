#!/usr/bin/env node
// figma-roblox-mcp — a stdio MCP server that reads Figma files via the REST API and
// converts frames into Roblox GUI (Luau) code.
//
// Why REST + a personal access token instead of Figma's official MCP:
// Figma's hosted MCP (https://mcp.figma.com/mcp) only speaks HTTP and REFUSES dynamic
// client registration (403 Forbidden at registerClient), so stdio-only clients bridging
// through mcp-remote can never complete OAuth. The REST API takes a plain
// X-Figma-Token header, which works from anywhere with zero OAuth dance.

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { CallToolRequestSchema, ListToolsRequestSchema } from "@modelcontextprotocol/sdk/types.js";
import { writeFileSync, mkdirSync } from "node:fs";
import { dirname } from "node:path";
import { figmaNodeToRoblox, sanitizeName } from "./convert.js";

const API = "https://api.figma.com/v1";
const TOKEN = process.env.FIGMA_TOKEN || process.env.FIGMA_ACCESS_TOKEN || "";

function need(v, name) {
  if (!v) throw new Error(`Missing required argument: ${name}`);
  return v;
}

// Accepts a raw key or a full URL like https://figma.com/design/<key>/<name>?node-id=1-2
function parseFileKey(input) {
  const s = String(input || "").trim();
  const m = s.match(/figma\.com\/(?:file|design|proto)\/([A-Za-z0-9]+)/);
  if (m) return m[1];
  return s;
}
// Figma URLs use "1-2" but the API wants "1:2"
function normalizeNodeId(input) {
  const s = String(input || "").trim();
  const m = s.match(/node-id=([0-9]+[-:][0-9]+)/);
  const raw = m ? m[1] : s;
  return raw.replace("-", ":");
}

async function figma(path) {
  if (!TOKEN) {
    throw new Error(
      "FIGMA_TOKEN is not set. Create a personal access token at " +
      "figma.com -> Settings -> Security -> Personal access tokens, then put it in the " +
      "server's env config as FIGMA_TOKEN."
    );
  }
  const res = await fetch(`${API}${path}`, { headers: { "X-Figma-Token": TOKEN } });
  if (!res.ok) {
    const body = await res.text().catch(() => "");
    if (res.status === 403) throw new Error(`Figma 403 Forbidden — token invalid/expired, or it lacks access to this file. ${body}`);
    if (res.status === 404) throw new Error(`Figma 404 — file or node not found. Check the file key. ${body}`);
    if (res.status === 429) throw new Error(`Figma 429 — rate limited. Wait and retry. ${body}`);
    throw new Error(`Figma API ${res.status}: ${body}`);
  }
  return res.json();
}

// Collect frame-ish nodes for a quick index of what's in a file.
function collectFrames(node, page, out, depth = 0) {
  if (!node) return;
  const framey = ["FRAME", "COMPONENT", "COMPONENT_SET", "INSTANCE", "GROUP"];
  if (framey.includes(node.type)) {
    const b = node.absoluteBoundingBox;
    out.push({
      id: node.id,
      name: node.name,
      type: node.type,
      page,
      depth,
      size: b ? `${Math.round(b.width)}x${Math.round(b.height)}` : "?",
      children: Array.isArray(node.children) ? node.children.length : 0,
    });
  }
  if (Array.isArray(node.children) && depth < 3) {
    for (const c of node.children) collectFrames(c, page, out, depth + 1);
  }
}

function summarize(node, depth = 0, max = 2) {
  if (!node) return null;
  const b = node.absoluteBoundingBox;
  const o = {
    id: node.id, name: node.name, type: node.type,
    box: b ? { x: Math.round(b.x), y: Math.round(b.y), w: Math.round(b.width), h: Math.round(b.height) } : undefined,
  };
  if (node.characters) o.text = node.characters.slice(0, 80);
  if (Array.isArray(node.children)) {
    o.childCount = node.children.length;
    if (depth < max) o.children = node.children.map((c) => summarize(c, depth + 1, max));
  }
  return o;
}

const TOOLS = [
  {
    name: "figma_file_info",
    description: "Read a Figma file's metadata + its pages and top-level frames. Start here: give it a file key or a full Figma URL. Returns the frame ids you feed to the other tools.",
    inputSchema: {
      type: "object",
      properties: { file: { type: "string", description: "Figma file key or full figma.com URL" } },
      required: ["file"],
    },
  },
  {
    name: "figma_list_frames",
    description: "List every frame/component/group in the file (up to 3 levels deep) with id, name, page and pixel size. Use it to find the frame you want to convert.",
    inputSchema: {
      type: "object",
      properties: {
        file: { type: "string", description: "Figma file key or URL" },
        filter: { type: "string", description: "Optional case-insensitive substring to match against the frame name" },
      },
      required: ["file"],
    },
  },
  {
    name: "figma_get_node",
    description: "Inspect one node's structure (id, type, box, text, children) without converting it. Useful to check a frame before generating code.",
    inputSchema: {
      type: "object",
      properties: {
        file: { type: "string", description: "Figma file key or URL" },
        node: { type: "string", description: 'Node id ("1:23") or a URL containing node-id=1-23' },
        depth: { type: "number", description: "How many child levels to include (default 2)" },
      },
      required: ["file", "node"],
    },
  },
  {
    name: "figma_to_roblox",
    description: "THE MAIN TOOL. Converts a Figma frame into ready-to-run Roblox GUI Luau code: Frames/TextLabels with UDim2 offsets, colors, UICorner, UIStroke, UIGradient, UIListLayout from auto-layout. Optionally writes the .lua to disk.",
    inputSchema: {
      type: "object",
      properties: {
        file: { type: "string", description: "Figma file key or URL" },
        node: { type: "string", description: 'Frame node id ("1:23") or a URL containing node-id=1-23' },
        guiName: { type: "string", description: "Name for the generated ScreenGui (defaults to the frame name)" },
        parentTo: { type: "string", enum: ["PlayerGui", "CoreGui", "gethui"], description: "Where the ScreenGui parents. Use gethui for exploit UIs (default PlayerGui)" },
        maxNodes: { type: "number", description: "Safety cap on emitted instances (default 400)" },
        outFile: { type: "string", description: "Optional absolute path to write the .lua file to" },
      },
      required: ["file", "node"],
    },
  },
  {
    name: "figma_export_image",
    description: "Get a rendered PNG/SVG URL for a node (for image fills, icons, logos). You still need to upload the image to Roblox to get an asset id.",
    inputSchema: {
      type: "object",
      properties: {
        file: { type: "string", description: "Figma file key or URL" },
        node: { type: "string", description: "Node id or URL" },
        format: { type: "string", enum: ["png", "svg", "jpg", "pdf"], description: "Default png" },
        scale: { type: "number", description: "1-4, default 2" },
      },
      required: ["file", "node"],
    },
  },
  {
    name: "figma_get_styles",
    description: "List the file's published colour/text styles and local variables — handy for building a consistent Roblox theme table.",
    inputSchema: {
      type: "object",
      properties: { file: { type: "string", description: "Figma file key or URL" } },
      required: ["file"],
    },
  },
];

const server = new Server(
  { name: "figma-roblox-mcp", version: "1.0.0" },
  { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({ tools: TOOLS }));

async function fetchNode(fileKey, nodeId) {
  const data = await figma(`/files/${fileKey}/nodes?ids=${encodeURIComponent(nodeId)}&geometry=paths`);
  const entry = data.nodes?.[nodeId];
  if (!entry || !entry.document) {
    const got = Object.keys(data.nodes || {}).join(", ");
    throw new Error(`Node ${nodeId} not found in file. Returned ids: ${got || "(none)"}`);
  }
  return entry.document;
}

const text = (s) => ({ content: [{ type: "text", text: typeof s === "string" ? s : JSON.stringify(s, null, 2) }] });

server.setRequestHandler(CallToolRequestSchema, async (req) => {
  const { name, arguments: a = {} } = req.params;
  try {
    if (name === "figma_file_info") {
      const key = parseFileKey(need(a.file, "file"));
      const data = await figma(`/files/${key}?depth=2`);
      const pages = (data.document?.children || []).map((p) => ({
        page: p.name,
        frames: (p.children || []).map((c) => ({ id: c.id, name: c.name, type: c.type })),
      }));
      return text({ fileKey: key, name: data.name, lastModified: data.lastModified, version: data.version, pages });
    }

    if (name === "figma_list_frames") {
      const key = parseFileKey(need(a.file, "file"));
      const data = await figma(`/files/${key}`);
      const out = [];
      for (const page of data.document?.children || []) {
        for (const child of page.children || []) collectFrames(child, page.name, out, 0);
      }
      let frames = out;
      if (a.filter) {
        const f = String(a.filter).toLowerCase();
        frames = frames.filter((x) => String(x.name).toLowerCase().includes(f));
      }
      return text({ fileKey: key, count: frames.length, frames: frames.slice(0, 200) });
    }

    if (name === "figma_get_node") {
      const key = parseFileKey(need(a.file, "file"));
      const id = normalizeNodeId(need(a.node, "node"));
      const doc = await fetchNode(key, id);
      return text(summarize(doc, 0, a.depth ?? 2));
    }

    if (name === "figma_to_roblox") {
      const key = parseFileKey(need(a.file, "file"));
      const id = normalizeNodeId(need(a.node, "node"));
      const doc = await fetchNode(key, id);
      const res = figmaNodeToRoblox(doc, {
        guiName: a.guiName ? sanitizeName(a.guiName) : undefined,
        parentTo: a.parentTo,
        maxNodes: a.maxNodes,
      });
      let wrote = null;
      if (a.outFile) {
        mkdirSync(dirname(a.outFile), { recursive: true });
        writeFileSync(a.outFile, res.code, "utf8");
        wrote = a.outFile;
      }
      const header =
        `-- ${res.nodeCount} instances emitted from "${doc.name}"` +
        (res.skipped.length ? ` (maxNodes cap hit; ${res.skipped.length} skipped)` : "") +
        (wrote ? `\n-- written to ${wrote}` : "");
      return text(`${header}\n\n${res.code}`);
    }

    if (name === "figma_export_image") {
      const key = parseFileKey(need(a.file, "file"));
      const id = normalizeNodeId(need(a.node, "node"));
      const fmt = a.format || "png";
      const scale = Math.max(1, Math.min(4, a.scale || 2));
      const data = await figma(`/images/${key}?ids=${encodeURIComponent(id)}&format=${fmt}&scale=${scale}`);
      const url = data.images?.[id];
      if (!url) throw new Error(`Figma returned no image for ${id}. ${data.err || ""}`);
      return text({ nodeId: id, format: fmt, scale, url, note: "Download this and upload it to Roblox to get an asset id." });
    }

    if (name === "figma_get_styles") {
      const key = parseFileKey(need(a.file, "file"));
      const data = await figma(`/files/${key}`);
      const styles = Object.entries(data.styles || {}).map(([id, s]) => ({ id, name: s.name, type: s.styleType }));
      return text({ fileKey: key, count: styles.length, styles });
    }

    throw new Error(`Unknown tool: ${name}`);
  } catch (err) {
    return { content: [{ type: "text", text: `ERROR: ${err.message}` }], isError: true };
  }
});

const transport = new StdioServerTransport();
await server.connect(transport);
console.error("figma-roblox-mcp ready" + (TOKEN ? "" : " (WARNING: FIGMA_TOKEN not set)"));
