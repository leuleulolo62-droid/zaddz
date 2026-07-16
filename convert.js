// Figma node tree -> Roblox GUI (Luau) source.
//
// Coordinate model: Figma gives every node an absoluteBoundingBox in page space.
// Roblox children are positioned relative to their parent, so each child's offset is
// (child.absolute - parent.absolute). AnchorPoint stays 0,0 because Figma's origin is
// also top-left, which makes the mapping 1:1 with no fudging.

const RESERVED = new Set([
  "and","break","do","else","elseif","end","false","for","function","if","in",
  "local","nil","not","or","repeat","return","then","true","until","while",
]);

// --- helpers ---------------------------------------------------------------

function sanitizeName(name, fallback) {
  let n = String(name || fallback || "Node")
    .replace(/[^A-Za-z0-9_]/g, "_")
    .replace(/^_+|_+$/g, "");
  if (!n) n = fallback || "Node";
  if (/^[0-9]/.test(n)) n = "_" + n;
  if (RESERVED.has(n)) n = n + "_";
  return n;
}

function luaStr(s) {
  return '"' + String(s ?? "").replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n").replace(/\r/g, "") + '"';
}

const r = (n) => Math.round((Number(n) || 0) * 1000) / 1000;

function color3(c) {
  if (!c) return "Color3.fromRGB(255, 255, 255)";
  const to255 = (v) => Math.round(Math.max(0, Math.min(1, Number(v) || 0)) * 255);
  return `Color3.fromRGB(${to255(c.r)}, ${to255(c.g)}, ${to255(c.b)})`;
}

// Figma opacity(1=opaque) -> Roblox Transparency(0=opaque)
function transparency(alpha, nodeOpacity) {
  const a = (alpha === undefined ? 1 : alpha) * (nodeOpacity === undefined ? 1 : nodeOpacity);
  return r(1 - Math.max(0, Math.min(1, a)));
}

function firstVisible(list) {
  if (!Array.isArray(list)) return null;
  return list.find((p) => p && p.visible !== false) || null;
}

// Figma font family/weight -> closest Enum.Font. Roblox's enum is a fixed set, so this
// is a best-effort mapping; unmatched families fall back to Gotham.
function mapFont(style) {
  const fam = String(style?.fontFamily || "").toLowerCase();
  const w = Number(style?.fontWeight) || 400;
  const bold = w >= 600;
  const semi = w >= 500 && w < 600;
  if (fam.includes("source sans") || fam.includes("sourcesans")) return bold ? "Enum.Font.SourceSansBold" : "Enum.Font.SourceSans";
  if (fam.includes("roboto mono") || fam.includes("mono") || fam.includes("code") || fam.includes("consol")) return "Enum.Font.Code";
  if (fam.includes("arial") || fam.includes("helvetica")) return bold ? "Enum.Font.ArialBold" : "Enum.Font.Arial";
  if (fam.includes("montserrat") || fam.includes("poppins") || fam.includes("inter") ||
      fam.includes("roboto") || fam.includes("gotham") || fam.includes("sf pro") || fam.includes("segoe")) {
    if (bold) return "Enum.Font.GothamBold";
    if (semi) return "Enum.Font.GothamMedium";
    return "Enum.Font.Gotham";
  }
  if (bold) return "Enum.Font.GothamBold";
  if (semi) return "Enum.Font.GothamMedium";
  return "Enum.Font.Gotham";
}

function mapXAlign(a) {
  if (a === "LEFT") return "Enum.TextXAlignment.Left";
  if (a === "RIGHT") return "Enum.TextXAlignment.Right";
  return "Enum.TextXAlignment.Center";
}
function mapYAlign(a) {
  if (a === "TOP") return "Enum.TextYAlignment.Top";
  if (a === "BOTTOM") return "Enum.TextYAlignment.Bottom";
  return "Enum.TextYAlignment.Center";
}

// Which Roblox class a Figma node becomes.
function classFor(node) {
  switch (node.type) {
    case "TEXT": return "TextLabel";
    case "FRAME":
    case "GROUP":
    case "COMPONENT":
    case "COMPONENT_SET":
    case "INSTANCE":
    case "RECTANGLE":
    case "ELLIPSE":
    case "VECTOR":
    case "STAR":
    case "POLYGON":
    case "LINE":
    case "BOOLEAN_OPERATION":
      return "Frame";
    default: return "Frame";
  }
}

// --- emitter ---------------------------------------------------------------

class Emitter {
  constructor(opts) {
    this.lines = [];
    this.used = new Map();
    this.opts = opts;
    this.count = 0;
    this.skipped = [];
  }
  varName(base) {
    let n = sanitizeName(base, "Node");
    const seen = this.used.get(n) || 0;
    this.used.set(n, seen + 1);
    return seen === 0 ? n : `${n}_${seen}`;
  }
  push(l) { this.lines.push(l); }
}

function emitFills(e, v, node) {
  const fill = firstVisible(node.fills);
  if (!fill) {
    e.push(`${v}.BackgroundTransparency = 1`);
    return;
  }
  if (fill.type === "SOLID") {
    e.push(`${v}.BackgroundColor3 = ${color3(fill.color)}`);
    e.push(`${v}.BackgroundTransparency = ${transparency(fill.opacity, node.opacity)}`);
    return;
  }
  if (fill.type && fill.type.startsWith("GRADIENT")) {
    // Roblox has no gradient fill on the instance itself: the base colour is the first
    // stop and a UIGradient child does the ramp.
    const stops = Array.isArray(fill.gradientStops) ? fill.gradientStops : [];
    const base = stops[0]?.color;
    e.push(`${v}.BackgroundColor3 = ${color3(base)}`);
    e.push(`${v}.BackgroundTransparency = ${transparency(fill.opacity, node.opacity)}`);
    if (stops.length >= 2) {
      const seq = stops
        .map((s) => `ColorSequenceKeypoint.new(${r(Math.max(0, Math.min(1, s.position)))}, ${color3(s.color)})`)
        .join(", ");
      const g = `${v}_Gradient`;
      e.push(`local ${g} = Instance.new("UIGradient")`);
      e.push(`${g}.Color = ColorSequence.new({ ${seq} })`);
      // Figma gradientHandlePositions -> rotation. Handle[0]=start, [1]=end.
      const h = fill.gradientHandlePositions;
      if (h && h[0] && h[1]) {
        const ang = Math.atan2(h[1].y - h[0].y, h[1].x - h[0].x) * (180 / Math.PI);
        e.push(`${g}.Rotation = ${r(ang)}`);
      }
      e.push(`${g}.Parent = ${v}`);
    }
    return;
  }
  if (fill.type === "IMAGE") {
    // Image fills need the asset uploaded to Roblox; emit a marker instead of a fake id.
    e.push(`${v}.BackgroundColor3 = Color3.fromRGB(30, 30, 30)`);
    e.push(`${v}.BackgroundTransparency = 0`);
    e.push(`-- TODO image fill: export this node (figma_export_image) and upload it, then use an ImageLabel`);
    return;
  }
  e.push(`${v}.BackgroundTransparency = 1`);
}

function emitCorner(e, v, node) {
  const cr = node.cornerRadius;
  const radii = node.rectangleCornerRadii;
  let radius = null;
  if (typeof cr === "number" && cr > 0) radius = cr;
  else if (Array.isArray(radii) && radii.some((x) => x > 0)) radius = Math.max(...radii); // Roblox UICorner is uniform
  if (node.type === "ELLIPSE") {
    const c = `${v}_Corner`;
    e.push(`local ${c} = Instance.new("UICorner")`);
    e.push(`${c}.CornerRadius = UDim.new(1, 0) -- ELLIPSE`);
    e.push(`${c}.Parent = ${v}`);
    return;
  }
  if (radius) {
    const c = `${v}_Corner`;
    e.push(`local ${c} = Instance.new("UICorner")`);
    e.push(`${c}.CornerRadius = UDim.new(0, ${r(radius)})`);
    e.push(`${c}.Parent = ${v}`);
  }
}

function emitStroke(e, v, node) {
  const s = firstVisible(node.strokes);
  if (!s || !node.strokeWeight) return;
  const st = `${v}_Stroke`;
  e.push(`local ${st} = Instance.new("UIStroke")`);
  e.push(`${st}.Color = ${color3(s.color)}`);
  e.push(`${st}.Thickness = ${r(node.strokeWeight)}`);
  e.push(`${st}.Transparency = ${transparency(s.opacity, node.opacity)}`);
  if (node.strokeAlign === "INSIDE") e.push(`${st}.ApplyStrokeMode = Enum.ApplyStrokeMode.Border`);
  e.push(`${st}.Parent = ${v}`);
}

function emitText(e, v, node) {
  e.push(`${v}.Text = ${luaStr(node.characters || "")}`);
  const st = node.style || {};
  e.push(`${v}.Font = ${mapFont(st)}`);
  e.push(`${v}.TextSize = ${r(st.fontSize || 14)}`);
  const fill = firstVisible(node.fills);
  e.push(`${v}.TextColor3 = ${color3(fill?.color || { r: 1, g: 1, b: 1 })}`);
  if (fill) e.push(`${v}.TextTransparency = ${transparency(fill.opacity, node.opacity)}`);
  e.push(`${v}.TextXAlignment = ${mapXAlign(st.textAlignHorizontal)}`);
  e.push(`${v}.TextYAlignment = ${mapYAlign(st.textAlignVertical)}`);
  e.push(`${v}.BackgroundTransparency = 1`);
  e.push(`${v}.TextWrapped = true`);
}

// Figma auto-layout -> UIListLayout (the closest Roblox equivalent).
function emitAutoLayout(e, v, node) {
  const mode = node.layoutMode;
  if (mode !== "HORIZONTAL" && mode !== "VERTICAL") return;
  const l = `${v}_Layout`;
  e.push(`local ${l} = Instance.new("UIListLayout")`);
  e.push(`${l}.FillDirection = ${mode === "HORIZONTAL" ? "Enum.FillDirection.Horizontal" : "Enum.FillDirection.Vertical"}`);
  e.push(`${l}.Padding = UDim.new(0, ${r(node.itemSpacing || 0)})`);
  e.push(`${l}.SortOrder = Enum.SortOrder.LayoutOrder`);
  const pa = node.primaryAxisAlignItems, ca = node.counterAxisAlignItems;
  if (mode === "VERTICAL") {
    e.push(`${l}.VerticalAlignment = ${pa === "CENTER" ? "Enum.VerticalAlignment.Center" : pa === "MAX" ? "Enum.VerticalAlignment.Bottom" : "Enum.VerticalAlignment.Top"}`);
    e.push(`${l}.HorizontalAlignment = ${ca === "CENTER" ? "Enum.HorizontalAlignment.Center" : ca === "MAX" ? "Enum.HorizontalAlignment.Right" : "Enum.HorizontalAlignment.Left"}`);
  } else {
    e.push(`${l}.HorizontalAlignment = ${pa === "CENTER" ? "Enum.HorizontalAlignment.Center" : pa === "MAX" ? "Enum.HorizontalAlignment.Right" : "Enum.HorizontalAlignment.Left"}`);
    e.push(`${l}.VerticalAlignment = ${ca === "CENTER" ? "Enum.VerticalAlignment.Center" : ca === "MAX" ? "Enum.VerticalAlignment.Bottom" : "Enum.VerticalAlignment.Top"}`);
  }
  e.push(`${l}.Parent = ${v}`);
  const pl = node.paddingLeft || 0, pr_ = node.paddingRight || 0, pt = node.paddingTop || 0, pb = node.paddingBottom || 0;
  if (pl || pr_ || pt || pb) {
    const p = `${v}_Padding`;
    e.push(`local ${p} = Instance.new("UIPadding")`);
    e.push(`${p}.PaddingLeft = UDim.new(0, ${r(pl)})`);
    e.push(`${p}.PaddingRight = UDim.new(0, ${r(pr_)})`);
    e.push(`${p}.PaddingTop = UDim.new(0, ${r(pt)})`);
    e.push(`${p}.PaddingBottom = UDim.new(0, ${r(pb)})`);
    e.push(`${p}.Parent = ${v}`);
  }
}

function walk(e, node, parentVar, parentBox, depth, order) {
  if (!node || node.visible === false) return;
  if (e.opts.maxNodes && e.count >= e.opts.maxNodes) {
    e.skipped.push(node.name || node.type);
    return;
  }
  e.count++;

  const box = node.absoluteBoundingBox || parentBox || { x: 0, y: 0, width: 100, height: 100 };
  const cls = classFor(node);
  const v = e.varName(node.name || cls);

  const relX = r((box.x || 0) - (parentBox?.x || 0));
  const relY = r((box.y || 0) - (parentBox?.y || 0));
  const w = r(box.width || 0);
  const h = r(box.height || 0);

  e.push("");
  e.push(`-- ${node.type} "${String(node.name || "").replace(/\n/g, " ")}"`);
  e.push(`local ${v} = Instance.new(${luaStr(cls)})`);
  e.push(`${v}.Name = ${luaStr(sanitizeName(node.name, cls))}`);
  e.push(`${v}.Size = UDim2.fromOffset(${w}, ${h})`);
  e.push(`${v}.Position = UDim2.fromOffset(${relX}, ${relY})`);
  e.push(`${v}.BorderSizePixel = 0`);
  if (order !== undefined) e.push(`${v}.LayoutOrder = ${order}`);

  if (cls === "TextLabel") {
    emitText(e, v, node);
  } else {
    emitFills(e, v, node);
  }
  emitCorner(e, v, node);
  emitStroke(e, v, node);
  if (node.rotation) {
    e.push(`${v}.Rotation = ${r(-(node.rotation * 180) / Math.PI)} -- Figma rotation is radians + CCW`);
  }
  if (node.clipsContent) e.push(`${v}.ClipsDescendants = true`);
  emitAutoLayout(e, v, node);
  e.push(`${v}.Parent = ${parentVar}`);

  const kids = Array.isArray(node.children) ? node.children : [];
  let i = 0;
  for (const child of kids) {
    walk(e, child, v, box, depth + 1, i);
    i++;
  }
}

/**
 * @param {object} node  a Figma node (usually a FRAME) from the REST API
 * @param {object} opts  { guiName, parentTo: "CoreGui"|"PlayerGui"|"gethui", maxNodes }
 * @returns {{ code: string, nodeCount: number, skipped: string[] }}
 */
export function figmaNodeToRoblox(node, opts = {}) {
  const o = {
    guiName: opts.guiName || sanitizeName(node?.name, "FigmaGui"),
    parentTo: opts.parentTo || "PlayerGui",
    maxNodes: opts.maxNodes || 400,
  };
  const e = new Emitter(o);

  e.push(`-- Generated from Figma node "${String(node?.name || "").replace(/\n/g, " ")}" (${node?.type})`);
  e.push(`-- by figma-roblox-mcp. Offsets are absolute pixels (1 Figma px = 1 Roblox offset).`);
  e.push("");
  const gui = e.varName(o.guiName);
  e.push(`local ${gui} = Instance.new("ScreenGui")`);
  e.push(`${gui}.Name = ${luaStr(o.guiName)}`);
  e.push(`${gui}.ResetOnSpawn = false`);
  e.push(`${gui}.ZIndexBehavior = Enum.ZIndexBehavior.Sibling`);
  if (o.parentTo === "CoreGui") {
    e.push(`${gui}.Parent = game:GetService("CoreGui")`);
  } else if (o.parentTo === "gethui") {
    e.push(`${gui}.Parent = (gethui and gethui()) or game:GetService("CoreGui")`);
  } else {
    e.push(`${gui}.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")`);
  }

  // The root frame anchors at 0,0 of the ScreenGui; its own children stay relative to it.
  const rootBox = node?.absoluteBoundingBox || { x: 0, y: 0, width: 0, height: 0 };
  walk(e, node, gui, rootBox, 0, undefined);

  e.push("");
  e.push(`return ${gui}`);

  return { code: e.lines.join("\n"), nodeCount: e.count, skipped: e.skipped };
}

export { sanitizeName };
