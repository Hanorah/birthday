import * as THREE from 'three';
import { GLTFLoader } from './vendor/addons/loaders/GLTFLoader.js';
import { LETTERS, CONFIG } from './story.js';
import { CAR_GLB } from './assets/car_glb.js';
import { TERRAIN_GLB } from './assets/terrain_glb.js';
import { SCENERY_GLB } from './assets/scenery_glb.js';

// =====================================================================
//  HAPPY BIRTHDAY UNCLE MO — birthday drive
//  Drive around the island (layout: Bruno Simon's folio-2025 terrain map),
//  collect candles, dodge obstacles, grab power-ups, open 10 letters.
// =====================================================================

const isTouch = matchMedia('(pointer: coarse)').matches || 'ontouchstart' in window;
if (isTouch) document.body.classList.add('touch');
const $ = (id) => document.getElementById(id);
const rand = (() => { let s = 16111987; return () => (s = (s * 16807) % 2147483647) / 2147483647; })();

// ------------------------------------------------------------------ renderer / scene
const canvas = $('c');
const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, powerPreference: 'high-performance' });
renderer.setPixelRatio(Math.min(devicePixelRatio, isTouch ? 1.5 : 2));
renderer.setSize(innerWidth, innerHeight);
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.05;

const scene = new THREE.Scene();
const FOG = new THREE.Color('#f6d9b8');
scene.fog = new THREE.Fog(FOG, 80, 200);
const camera = new THREE.PerspectiveCamera(38, innerWidth / innerHeight, 0.5, 600);
const CAM_OFFSET = new THREE.Vector3(0, 16, 19);

const hemi = new THREE.HemisphereLight('#fff1dc', '#7a8f6a', 1.25);
scene.add(hemi);
const sun = new THREE.DirectionalLight('#ffe2b8', 2.7);
sun.castShadow = true;
sun.shadow.mapSize.set(isTouch ? 1024 : 2048, isTouch ? 1024 : 2048);
Object.assign(sun.shadow.camera, { left: -32, right: 32, top: 32, bottom: -32, near: 1, far: 140 });
sun.shadow.bias = -0.0006;
scene.add(sun, sun.target);

const sky = new THREE.Mesh(new THREE.SphereGeometry(500, 32, 16), new THREE.ShaderMaterial({
  side: THREE.BackSide, depthWrite: false, fog: false,
  uniforms: { top: { value: new THREE.Color('#4f9be0') }, mid: { value: new THREE.Color('#9fd0f0') }, bottom: { value: new THREE.Color('#ffd9b0') } },
  vertexShader: 'varying vec3 vP; void main(){ vP = normalize(position); gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.); }',
  fragmentShader: `uniform vec3 top; uniform vec3 mid; uniform vec3 bottom; varying vec3 vP;
    void main(){ float y = vP.y; vec3 c = mix(bottom, mid, smoothstep(-0.05, 0.18, y)); c = mix(c, top, smoothstep(0.18, 0.7, y)); gl_FragColor = vec4(c,1.); }`,
}));
scene.add(sky);

// ------------------------------------------------------------------ loading
const manager = new THREE.LoadingManager();
manager.onProgress = (_u, l, t) => { $('loadbar').firstElementChild.style.width = (l / t * 100) + '%'; };
const texLoader = new THREE.TextureLoader(manager);
const letterTex = LETTERS.map((L) => { const t = texLoader.load(L.image); t.colorSpace = THREE.SRGBColorSpace; return t; });
$('title').style.backgroundImage = `url(${LETTERS[LETTERS.length - 1].image})`;

let carModel = null;
manager.itemStart('car');
{
  const bin = Uint8Array.from(atob(CAR_GLB), (c) => c.charCodeAt(0));
  new GLTFLoader().parse(bin.buffer, './', (g) => { carModel = g.scene; manager.itemEnd('car'); }, () => manager.itemEnd('car'));
}
let terrainModel = null, sceneryModel = null;
for (const [b64, set] of [[TERRAIN_GLB, (g) => (terrainModel = g)], [SCENERY_GLB, (g) => (sceneryModel = g)]]) {
  manager.itemStart(b64.slice(0, 12));
  const bin = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
  new GLTFLoader().parse(bin.buffer, './', (g) => { set(g.scene); manager.itemEnd(b64.slice(0, 12)); }, () => manager.itemEnd(b64.slice(0, 12)));
}
let map = null; // terrain classification
manager.itemStart('terrain');
const mapImg = new Image();
mapImg.onload = () => {
  const c = document.createElement('canvas'); c.width = mapImg.width; c.height = mapImg.height;
  const g = c.getContext('2d'); g.drawImage(mapImg, 0, 0);
  map = { w: c.width, h: c.height, data: g.getImageData(0, 0, c.width, c.height).data };
  manager.itemEnd('terrain');
};
mapImg.src = 'assets/terrain.png';

// ------------------------------------------------------------------ terrain map helpers
const WORLD = 192;                     // folio island size (terrain.glb spans -96..96)
function px(x, z) { return [Math.floor((x / WORLD + 0.5) * map.w), Math.floor((z / WORLD + 0.5) * map.h)]; }
function sample(x, z) {
  const [i, j] = px(x, z);
  if (i < 0 || j < 0 || i >= map.w || j >= map.h) return { r: 0, g: 0, b: 1 };
  const k = (j * map.w + i) * 4; const d = map.data;
  return { r: d[k] / 255, g: d[k + 1] / 255, b: d[k + 2] / 255 };
}
function kind(x, z) {
  const s = sample(x, z);
  if (s.b > Math.max(s.r, s.g) && s.b > 0.35) return 'water';
  if (s.r > 0.5 && s.r >= s.g) return 'path';
  if (s.g > 0.4) return 'grass';
  return 'ground';
}
function randomSpot(type, avoid = [], minDist = 0, tries = 4000) {
  for (let n = 0; n < tries; n++) {
    const x = (rand() - 0.5) * WORLD * 0.96, z = (rand() - 0.5) * WORLD * 0.96;
    if (kind(x, z) !== type) continue;
    if (avoid.some((p) => Math.hypot(p.x - x, p.z - z) < minDist)) continue;
    return new THREE.Vector3(x, 0, z);
  }
  return null;
}

// ------------------------------------------------------------------ world build
const flat = (color, extra = {}) => new THREE.MeshStandardMaterial({ color, flatShading: true, roughness: 0.9, ...extra });
const colliders = [];     // solid round things {x,z,r}
let water, spawn;

function terrainHeight(x, z) {
  const sm = sample(x, z);
  return -1.5 * THREE.MathUtils.clamp((sm.b - Math.max(sm.r, sm.g) + 0.1) * 2.5, 0, 1);
}
function buildTerrain() {
  let geo;
  terrainModel?.traverse((o) => { if (o.isMesh && !geo) geo = o.geometry.clone().applyMatrix4(o.matrixWorld); });
  if (!geo) { geo = new THREE.PlaneGeometry(WORLD, WORLD, 200, 200); geo.rotateX(-Math.PI / 2); }
  geo = geo.index ? geo.toNonIndexed() : geo;
  const pos = geo.attributes.position;
  const cols = new Float32Array(pos.count * 3);
  const cPath = new THREE.Color('#ecc58f'), cGrass = new THREE.Color('#8fc25a'), cGround = new THREE.Color('#a9b86a'), cBed = new THREE.Color('#2f6fb8');
  const tmp = new THREE.Color();
  for (let i = 0; i < pos.count; i++) {
    const x = pos.getX(i), z = pos.getZ(i);
    if (!terrainModel) pos.setY(i, terrainHeight(x, z));
    const sm = sample(x, z);
    const w = THREE.MathUtils.clamp((sm.b - Math.max(sm.r, sm.g) + 0.1) * 2.5, 0, 1);
    tmp.copy(cGround);
    tmp.lerp(cGrass, THREE.MathUtils.clamp(sm.g * 1.4 - sm.r * 0.6, 0, 1));
    tmp.lerp(cPath, THREE.MathUtils.clamp(sm.r * 1.3 - sm.g * 0.4, 0, 1));
    tmp.lerp(cBed, w);
    const v = 0.95 + ((i * 7919) % 97) / 97 * 0.08;
    cols[i * 3] = tmp.r * v; cols[i * 3 + 1] = tmp.g * v; cols[i * 3 + 2] = tmp.b * v;
  }
  geo.setAttribute('color', new THREE.BufferAttribute(cols, 3));
  geo.computeVertexNormals();
  const mesh = new THREE.Mesh(geo, new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 1, flatShading: true }));
  mesh.receiveShadow = true;
  scene.add(mesh);
  // sea around the island
  const sea = new THREE.Mesh(new THREE.RingGeometry(WORLD * 0.72, 700, 64), new THREE.MeshStandardMaterial({ color: '#2f6fb8', roughness: 1 }));
  sea.rotation.x = -Math.PI / 2; sea.position.y = -1.6; scene.add(sea);
  water = new THREE.Mesh(new THREE.PlaneGeometry(1400, 1400), new THREE.MeshStandardMaterial({ color: '#1f8ff0', roughness: 0.08, metalness: 0.1, transparent: true, opacity: 0.9, fog: true }));
  water.rotation.x = -Math.PI / 2; water.position.y = -0.45;
  scene.add(water);
  // Bruno's bridges and basalt rocks
  if (sceneryModel) {
    sceneryModel.traverse((o) => {
      if (/^hull|^ref/i.test(o.name)) o.visible = false;
      if (o.isMesh) { o.castShadow = true; o.receiveShadow = true; }
    });
    scene.add(sceneryModel);
    sceneryModel.updateMatrixWorld(true);
    sceneryModel.children.forEach((c) => {
      if (/basalt/i.test(c.name)) { const b = new THREE.Box3().setFromObject(c); const sz = b.getSize(new THREE.Vector3()); const ctr = b.getCenter(new THREE.Vector3()); colliders.push({ x: ctr.x, z: ctr.z, r: Math.min(sz.x, sz.z) * 0.45 }); }
    });
  }
}

function buildGrass() {
  // soft round bushes + little flowers (friendly, not spiky)
  const bushN = isTouch ? 260 : 420, flowerN = isTouch ? 1400 : 2600;
  const bush = new THREE.InstancedMesh(new THREE.IcosahedronGeometry(0.9, 1), new THREE.MeshStandardMaterial({ roughness: 0.9, flatShading: true }), bushN);
  const flower = new THREE.InstancedMesh(new THREE.IcosahedronGeometry(0.16, 0), new THREE.MeshStandardMaterial({ roughness: 0.6 }), flowerN);
  const m4 = new THREE.Matrix4(), q = new THREE.Quaternion(), c = new THREE.Color();
  const greens = ['#6fae4a', '#7fbf55', '#5f9e45', '#9acb5f'];
  const petals = ['#ffffff', '#ffd84d', '#ff9ec4', '#ff7f6e', '#c9a2ff', '#7fd1ff'];
  let b = 0, f = 0;
  for (let t = 0; t < 40000 && (b < bushN || f < flowerN); t++) {
    const x = (rand() - 0.5) * WORLD, z = (rand() - 0.5) * WORLD;
    const k = kind(x, z);
    if (k === 'water' || k === 'path') continue;
    if (b < bushN && rand() < 0.15) {
      const sc = 0.5 + rand() * 0.8;
      m4.compose(new THREE.Vector3(x, sc * 0.35, z), q.setFromEuler(new THREE.Euler(0, rand() * 6, 0)), new THREE.Vector3(sc, sc * 0.75, sc));
      bush.setMatrixAt(b, m4); bush.setColorAt(b++, c.set(greens[Math.floor(rand() * greens.length)]));
    } else if (f < flowerN) {
      m4.compose(new THREE.Vector3(x, 0.18, z), q.identity(), new THREE.Vector3(1, 1, 1));
      flower.setMatrixAt(f, m4); flower.setColorAt(f++, c.set(petals[Math.floor(rand() * petals.length)]));
    }
  }
  bush.count = b; flower.count = f;
  bush.castShadow = true; bush.receiveShadow = true;
  scene.add(bush, flower);
}
const grassTime = { value: 0 };

function tree(x, z) {
  const g = new THREE.Group(); g.position.set(x, 0, z);
  const s = 0.65 + rand() * 0.45; g.scale.setScalar(s); g.rotation.y = rand() * 6.28;
  const trunk = new THREE.Mesh(new THREE.CylinderGeometry(0.22, 0.34, 2.4, 6), flat('#6b3f3a')); trunk.position.y = 1.2; g.add(trunk);
  const leaf = ['#6fae4a', '#86c25a', '#f3a6b8', '#f6b26b', '#5f9e45'][Math.floor(rand() * 5)];
  for (let k = 0; k < 3; k++) {
    const b = new THREE.Mesh(new THREE.IcosahedronGeometry(1.5 - k * 0.22, 0), flat(leaf));
    b.position.set((rand() - 0.5) * 1.2, 3 + k * 0.75, (rand() - 0.5) * 1.2); g.add(b);
  }
  g.traverse((o) => { if (o.isMesh) { o.castShadow = true; o.receiveShadow = true; } });
  scene.add(g); colliders.push({ x, z, r: 0.8 * s });
}
function rockBlock(x, z) {
  const s = 1 + rand() * 2.2;
  const m = new THREE.Mesh(new THREE.BoxGeometry(s, s * (0.8 + rand()), s), flat(['#8a8f99', '#9aa0a8', '#7b808a'][Math.floor(rand() * 3)]));
  m.position.set(x, s * 0.35, z); m.rotation.y = rand() * 6.28; m.castShadow = true; m.receiveShadow = true;
  scene.add(m); colliders.push({ x, z, r: s * 0.6 });
}
function lantern(x, z) {
  const g = new THREE.Group(); g.position.set(x, 0, z);
  const post = new THREE.Mesh(new THREE.BoxGeometry(0.25, 2.2, 0.25), flat('#5a3d5c')); post.position.y = 1.1; g.add(post);
  const box = new THREE.Mesh(new THREE.BoxGeometry(0.8, 0.9, 0.8), new THREE.MeshStandardMaterial({ color: '#ffd27a', emissive: '#ffb347', emissiveIntensity: 1.6 }));
  box.position.y = 2.6; g.add(box);
  const cap = new THREE.Mesh(new THREE.ConeGeometry(0.7, 0.5, 4), flat('#5a3d5c')); cap.position.y = 3.3; cap.rotation.y = Math.PI / 4; g.add(cap);
  g.traverse((o) => { if (o.isMesh) o.castShadow = true; });
  scene.add(g); colliders.push({ x, z, r: 0.4 });
}

// ------------------------------------------------------------------ gameplay objects
const mailboxes = [];   // {pos, group, flag, glow, index}
const candles = [];     // {mesh, pos, taken}
const obstacles = [];   // {mesh, pos, type, knocked, vel, timer}
const muds = [];        // {pos, r}
const powerups = [];    // {mesh, pos, type, timer}

function makeLabelTexture(text, bg = '#3b2a4f', fg = '#ffd27a') {
  const c = document.createElement('canvas'); c.width = 256; c.height = 256; const g = c.getContext('2d');
  g.fillStyle = bg; g.beginPath(); g.arc(128, 128, 120, 0, Math.PI * 2); g.fill();
  g.fillStyle = fg; g.font = 'bold 140px Georgia, serif'; g.textAlign = 'center'; g.textBaseline = 'middle'; g.fillText(text, 128, 138);
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; return t;
}

function buildMailbox(pos, i) {
  const g = new THREE.Group(); g.position.copy(pos);
  const post = new THREE.Mesh(new THREE.BoxGeometry(0.35, 2, 0.35), flat('#6b4a3a')); post.position.y = 1; g.add(post);
  const body = new THREE.Mesh(new THREE.BoxGeometry(1.2, 1, 1.9), flat('#e85d75')); body.position.y = 2.4; g.add(body);
  const top = new THREE.Mesh(new THREE.CylinderGeometry(0.6, 0.6, 1.9, 12, 1, false, 0, Math.PI), flat('#e85d75'));
  top.rotation.z = Math.PI / 2; top.rotation.y = Math.PI / 2; top.position.y = 2.9; g.add(top);
  const flag = new THREE.Group(); flag.position.set(0.65, 2.5, -0.3);
  const fp = new THREE.Mesh(new THREE.BoxGeometry(0.08, 1.1, 0.08), flat('#ffd27a')); fp.position.y = 0.4; flag.add(fp);
  const ff = new THREE.Mesh(new THREE.BoxGeometry(0.06, 0.4, 0.55), flat('#ffd27a')); ff.position.set(0, 0.8, 0.25); flag.add(ff);
  g.add(flag);
  const num = new THREE.Sprite(new THREE.SpriteMaterial({ map: makeLabelTexture(String(i + 1)), depthTest: true }));
  num.scale.set(1.6, 1.6, 1); num.position.y = 4.6; g.add(num);
  const ring = new THREE.Mesh(new THREE.RingGeometry(2.6, 3.2, 40), new THREE.MeshBasicMaterial({ color: '#ffd27a', transparent: true, opacity: 0.0, toneMapped: false }));
  ring.rotation.x = -Math.PI / 2; ring.position.y = 0.08; g.add(ring);
  g.traverse((o) => { if (o.isMesh) o.castShadow = true; });
  scene.add(g);
  colliders.push({ x: pos.x, z: pos.z, r: 0.5 });
  mailboxes.push({ pos, group: g, flag, ring, num, index: i, opened: false });
}

let glowTex;
function getGlowTex() {
  if (glowTex) return glowTex;
  const c = document.createElement('canvas'); c.width = c.height = 128; const g = c.getContext('2d');
  const grd = g.createRadialGradient(64, 64, 0, 64, 64, 64);
  grd.addColorStop(0, 'rgba(255,240,180,1)'); grd.addColorStop(0.25, 'rgba(255,200,90,.6)'); grd.addColorStop(1, 'rgba(255,160,40,0)');
  g.fillStyle = grd; g.fillRect(0, 0, 128, 128);
  glowTex = new THREE.CanvasTexture(c); return glowTex;
}
const CANDLE_COLS = [['#ff8fb1', '#ffffff'], ['#7fd1ff', '#ffffff'], ['#ffd36e', '#ffffff'], ['#b9f27c', '#ffffff'], ['#c9a2ff', '#ffffff']];
function candleMesh(small = false) {
  const g = new THREE.Group();
  const [a, b] = CANDLE_COLS[Math.floor(rand() * CANDLE_COLS.length)];
  const R = small ? 0.07 : 0.22, SEG = small ? 0.09 : 0.24, N = small ? 4 : 5;
  for (let i = 0; i < N; i++) {
    const seg = new THREE.Mesh(new THREE.CylinderGeometry(R, R, SEG, 10), new THREE.MeshStandardMaterial({ color: i % 2 ? b : a, roughness: 0.5 }));
    seg.position.y = SEG * (i + 0.5); g.add(seg);
  }
  const top = SEG * N;
  const wick = new THREE.Mesh(new THREE.CylinderGeometry(R * 0.12, R * 0.12, R * 0.6, 4), new THREE.MeshBasicMaterial({ color: '#222' }));
  wick.position.y = top + R * 0.3; g.add(wick);
  const flame = new THREE.Group(); flame.position.y = top + R * 1.1;
  const outer = new THREE.Mesh(new THREE.SphereGeometry(R * 0.85, 10, 8), new THREE.MeshBasicMaterial({ color: '#ff9a2e', transparent: true, opacity: 0.9, toneMapped: false }));
  outer.scale.set(1, 1.9, 1); flame.add(outer);
  const inner = new THREE.Mesh(new THREE.SphereGeometry(R * 0.45, 8, 6), new THREE.MeshBasicMaterial({ color: '#fff6c8', toneMapped: false }));
  inner.scale.set(1, 1.7, 1); inner.position.y = -R * 0.2; flame.add(inner);
  const glow = new THREE.Sprite(new THREE.SpriteMaterial({ map: getGlowTex(), blending: THREE.AdditiveBlending, depthWrite: false, transparent: true }));
  glow.scale.setScalar(small ? 0.8 : 2.6); flame.add(glow);
  g.add(flame);
  g.userData.flame = flame;
  if (!small) {
    const ring = new THREE.Mesh(new THREE.TorusGeometry(0.75, 0.06, 6, 28), new THREE.MeshBasicMaterial({ color: '#ffd27a', toneMapped: false }));
    ring.rotation.x = Math.PI / 2; ring.position.y = 0.06; g.add(ring); g.userData.ring = ring;
    g.scale.setScalar(1.25);
  }
  g.children.forEach((m) => { if (m.isMesh) m.castShadow = true; });
  return g;
}

function obstacleMesh(type) {
  const g = new THREE.Group();
  if (type === 'cone') {
    const c = new THREE.Mesh(new THREE.ConeGeometry(0.45, 1.2, 8), flat('#ff7a2e')); c.position.y = 0.6; g.add(c);
    const band = new THREE.Mesh(new THREE.CylinderGeometry(0.27, 0.33, 0.2, 8), flat('#ffffff')); band.position.y = 0.65; g.add(band);
    const base = new THREE.Mesh(new THREE.BoxGeometry(0.9, 0.1, 0.9), flat('#ff7a2e')); base.position.y = 0.05; g.add(base);
  } else if (type === 'crate') {
    const b = new THREE.Mesh(new THREE.BoxGeometry(1.4, 1.4, 1.4), flat('#b8814f')); b.position.y = 0.7; g.add(b);
    const s = new THREE.Mesh(new THREE.BoxGeometry(1.45, 0.25, 1.45), flat('#8a5a33')); s.position.y = 0.7; g.add(s);
  } else { // barrier
    const bar = new THREE.Mesh(new THREE.BoxGeometry(3.2, 0.45, 0.25), flat('#ffffff')); bar.position.y = 1.0; g.add(bar);
    for (let k = -1; k <= 1; k += 2) { const stripe = new THREE.Mesh(new THREE.BoxGeometry(0.6, 0.47, 0.27), flat('#e8485d')); stripe.position.set(k * 0.8, 1.0, 0); g.add(stripe); }
    for (const sx of [-1.4, 1.4]) { const leg = new THREE.Mesh(new THREE.BoxGeometry(0.15, 1.0, 0.6), flat('#555')); leg.position.set(sx, 0.5, 0); g.add(leg); }
  }
  g.traverse((o) => { if (o.isMesh) o.castShadow = true; });
  return g;
}

const POWER = {
  turbo: { color: '#ff5a5a', label: '⚡ TURBO', time: 5 },
  magnet: { color: '#5ab0ff', label: '🧲 CANDLE MAGNET', time: 9 },
  shield: { color: '#7cf29a', label: '🛡 SHIELD', time: 9 },
};
function powerMesh(type) {
  const g = new THREE.Group();
  const core = new THREE.Mesh(new THREE.OctahedronGeometry(0.75, 0), new THREE.MeshStandardMaterial({ color: POWER[type].color, emissive: POWER[type].color, emissiveIntensity: 0.9, flatShading: true }));
  core.position.y = 1.5; g.add(core);
  const ring = new THREE.Mesh(new THREE.TorusGeometry(1.1, 0.07, 6, 24), new THREE.MeshBasicMaterial({ color: POWER[type].color, toneMapped: false }));
  ring.position.y = 1.5; g.add(ring);
  const icon = new THREE.Sprite(new THREE.SpriteMaterial({ map: makeLabelTexture({ turbo: '⚡', magnet: '◎', shield: '✚' }[type], '#ffffff', POWER[type].color) }));
  icon.scale.set(1, 1, 1); icon.position.y = 3; g.add(icon);
  return g;
}

function populate() {
  // spawn on the path nearest the bottom-centre of the map
  let best = null, bd = Infinity;
  for (let i = 0; i < 6000; i++) {
    const x = (rand() - 0.5) * WORLD, z = (rand() - 0.5) * WORLD;
    if (kind(x, z) !== 'path') continue;
    const d = Math.hypot(x, z - WORLD * 0.42);
    if (d < bd) { bd = d; best = new THREE.Vector3(x, 0, z); }
  }
  spawn = best || new THREE.Vector3();

  // mailboxes: spread out (farthest-point), then ordered as a tour from spawn
  const cand = [];
  for (let i = 0; i < 2500; i++) { const p = randomSpot('path', [], 0, 50); if (p) cand.push(p); }
  const chosen = [];
  let cur = spawn;
  const picks = [];
  while (picks.length < LETTERS.length && cand.length) {
    let bi = 0, bv = -1;
    for (let i = 0; i < cand.length; i++) {
      const dmin = Math.min(Math.hypot(cand[i].x - spawn.x, cand[i].z - spawn.z) * 1.2, ...picks.map((p) => Math.hypot(p.x - cand[i].x, p.z - cand[i].z)));
      if (dmin > bv) { bv = dmin; bi = i; }
    }
    picks.push(cand.splice(bi, 1)[0]);
  }
  while (picks.length) {   // greedy tour
    let bi = 0, bv = Infinity;
    picks.forEach((p, i) => { const d = Math.hypot(p.x - cur.x, p.z - cur.z); if (d < bv) { bv = d; bi = i; } });
    cur = picks.splice(bi, 1)[0]; chosen.push(cur);
  }
  // letters now open automatically — no mailboxes
  const keep = [spawn, ...chosen];

  // candles (more than needed so it never feels stingy)
  for (let i = 0; i < CONFIG.age + 22; i++) {
    const p = randomSpot('path', keep.concat(candles.map((c) => c.pos)), 7);
    if (!p) continue;
    const m = candleMesh(); m.position.copy(p); scene.add(m);
    candles.push({ mesh: m, pos: p, taken: false, phase: rand() * 6 });
  }
  // obstacles on the paths
  const avoid = keep.concat(candles.map((c) => c.pos));
  for (let i = 0; i < 46; i++) {
    const p = randomSpot('path', avoid, 5);
    if (!p) continue;
    const type = ['cone', 'cone', 'crate', 'barrier'][Math.floor(rand() * 4)];
    const m = obstacleMesh(type); m.position.copy(p); m.rotation.y = rand() * 6.28; scene.add(m);
    obstacles.push({ mesh: m, pos: p.clone(), home: p.clone(), rot: m.rotation.y, type, knocked: false, vel: new THREE.Vector3(), spin: 0, timer: 0 });
    avoid.push(p);
  }
  // mud puddles
  for (let i = 0; i < 0; i++) {   // mud removed
    const p = randomSpot('path', avoid, 8);
    if (!p) continue;
    const r = 2.5 + rand() * 1.5;
    const m = new THREE.Mesh(new THREE.CircleGeometry(r, 16), new THREE.MeshStandardMaterial({ color: '#5b3a2a', roughness: 0.3 }));
    m.rotation.x = -Math.PI / 2; m.position.set(p.x, 0.06, p.z); m.scale.set(1, 0.7 + rand() * 0.5, 1); scene.add(m);
    muds.push({ pos: p, r }); avoid.push(p);
  }
  // power-ups
  const types = ['turbo', 'magnet', 'shield'];
  for (let i = 0; i < 9; i++) {
    const p = randomSpot('path', avoid, 14);
    if (!p) continue;
    const type = types[i % 3];
    const m = powerMesh(type); m.position.copy(p); scene.add(m);
    powerups.push({ mesh: m, pos: p, type, timer: 0 });
    avoid.push(p);
  }
  // scenery
  for (let i = 0; i < (isTouch ? 70 : 110); i++) { const p = randomSpot(rand() < 0.6 ? 'ground' : 'grass', keep, 6); if (p) tree(p.x, p.z); }
  for (let i = 0; i < 60; i++) {
    const p = randomSpot('ground', keep, 4);
    if (p && ['water'].includes(kind(p.x + 4, p.z)) || (p && kind(p.x - 4, p.z) === 'water') || (p && kind(p.x, p.z + 4) === 'water')) rockBlock(p.x, p.z);
  }
  for (let i = 0; i < 40; i++) {
    const p = randomSpot('path', avoid, 10);
    if (!p) continue;
    // move lantern to the edge of the path
    for (let k = 0; k < 12; k++) {
      const a = rand() * 6.28; const q = new THREE.Vector3(p.x + Math.cos(a) * 6, 0, p.z + Math.sin(a) * 6);
      if (kind(q.x, q.z) !== 'path' && kind(q.x, q.z) !== 'water') { lantern(q.x, q.z); break; }
    }
  }
  buildCake();
}

let cake, cakePlate, cakeCandles = [], cakeState = 'hidden', cakeRiseT = 0;   // hidden -> rising -> ready -> wishing -> done
function buildCake() {
  const base = spawn.clone().add(new THREE.Vector3(0, 0, -10));
  cakePlate = new THREE.Group(); cakePlate.position.copy(base);
  const plate = new THREE.Mesh(new THREE.CylinderGeometry(4.2, 4.4, 0.3, 32), flat('#fff1e0')); plate.position.y = 0.15; cakePlate.add(plate);
  const rim = new THREE.Mesh(new THREE.TorusGeometry(4.3, 0.12, 6, 40), new THREE.MeshBasicMaterial({ color: '#ffd27a', toneMapped: false })); rim.rotation.x = Math.PI / 2; rim.position.y = 0.32; cakePlate.add(rim);
  const sign = new THREE.Sprite(new THREE.SpriteMaterial({ map: makeLabelTexture('39', '#ff8fb1', '#ffffff') })); sign.scale.set(2.4, 2.4, 1); sign.position.y = 3.2; cakePlate.add(sign);
  cakePlate.userData.sign = sign;
  scene.add(cakePlate);
  colliders.push({ x: base.x, z: base.z, r: 3.6 });

  cake = new THREE.Group(); cake.position.copy(base); cake.position.y = -7;
  const tiers = [[3.0, 1.6, '#fff1e0', '#ff8fb1'], [2.1, 1.3, '#fff1e0', '#7fd1ff'], [1.25, 1.0, '#fff1e0', '#ffd36e']];
  let y = 0.3; const tops = [];
  for (const [r, h, c, icing] of tiers) {
    const t = new THREE.Mesh(new THREE.CylinderGeometry(r, r, h, 32), flat(c)); t.position.y = y + h / 2; cake.add(t);
    const ic = new THREE.Mesh(new THREE.CylinderGeometry(r + 0.05, r + 0.05, 0.22, 32), flat(icing)); ic.position.y = y + h - 0.05; cake.add(ic);
    for (let k = 0; k < 14; k++) { const a = k / 14 * 6.28; const drip = new THREE.Mesh(new THREE.SphereGeometry(0.16, 6, 5), flat(icing)); drip.scale.y = 1.6; drip.position.set(Math.cos(a) * (r + 0.04), y + h - 0.3, Math.sin(a) * (r + 0.04)); cake.add(drip); }
    y += h; tops.push([r, y]);
  }
  // 39 candle slots: 15 + 14 + 10
  const layout = [[0, 15], [1, 14], [2, 10]];
  for (const [ti, n] of layout) {
    const [r, top] = tops[ti];
    for (let k = 0; k < n; k++) {
      const a = k / n * 6.28 + ti * 0.3;
      const c = candleMesh(true); c.scale.setScalar(1.7);
      c.position.set(Math.cos(a) * (r - 0.4), top, Math.sin(a) * (r - 0.4));
      c.visible = false; c.userData.flame.visible = false;
      cake.add(c); cakeCandles.push(c);
    }
  }
  cake.traverse((o) => { if (o.isMesh) o.castShadow = true; });
  scene.add(cake);
}
const cakeTop = () => cakePlate.position.clone().add(new THREE.Vector3(0, 5, 0));

// ------------------------------------------------------------------ car
const car = { group: new THREE.Group(), pos: new THREE.Vector3(), prev: new THREE.Vector3(), heading: Math.PI, speed: 0, steer: 0, wheels: [], spinners: [], body: null, spin: 0 };
scene.add(car.group);
let shieldBubble, arrow, beacon;
function buildCar() {
  if (carModel) {
    const chassis = carModel.getObjectByName('chassis001') || carModel.children[0];
    const wheel = carModel.getObjectByName('wheelContainer001');
    car.body = new THREE.Group(); chassis.position.set(0, 0, 0); car.body.add(chassis); car.body.position.y = 1.05; car.group.add(car.body);
    if (wheel) {
      wheel.position.set(0, 0, 0);
      [[1.25, 0.72, 1], [1.25, -0.72, -1], [-1.25, 0.72, 1], [-1.25, -0.72, -1]].forEach(([x, z, side], i) => {
        const holder = new THREE.Group(); holder.position.set(x, 0.45, z);
        const w = wheel.clone(true); w.position.set(0, 0, 0); if (side < 0) w.scale.z = -1;
        holder.add(w); car.group.add(holder); car.wheels.push({ holder, front: i < 2 });
        const cyl = w.getObjectByName('wheelCylinder001'); if (cyl) car.spinners.push(cyl);
      });
    }
    car.group.traverse((o) => { if (o.isMesh) { o.castShadow = true; o.receiveShadow = true; } });
  }
  shieldBubble = new THREE.Mesh(new THREE.SphereGeometry(2.6, 20, 14), new THREE.MeshBasicMaterial({ color: '#7cf29a', transparent: true, opacity: 0.22, depthWrite: false, toneMapped: false }));
  shieldBubble.position.y = 1.2; shieldBubble.visible = false; car.group.add(shieldBubble);
  arrow = new THREE.Group();
  const arrowMat = new THREE.MeshStandardMaterial({ color: '#ffd27a', emissive: '#ffb020', emissiveIntensity: 0.6, flatShading: true });
  const outline = new THREE.MeshBasicMaterial({ color: '#3a2a2a', side: THREE.BackSide });
  const shape = new THREE.Shape();
  shape.moveTo(-0.45, -1.6); shape.lineTo(0.45, -1.6); shape.lineTo(0.45, 0.2); shape.lineTo(1.15, 0.2); shape.lineTo(0, 1.7); shape.lineTo(-1.15, 0.2); shape.lineTo(-0.45, 0.2); shape.closePath();
  const geo = new THREE.ExtrudeGeometry(shape, { depth: 0.35, bevelEnabled: true, bevelThickness: 0.08, bevelSize: 0.08, bevelSegments: 1 });
  geo.translate(0, 0, -0.17); geo.rotateX(-Math.PI / 2);   // lies flat, points along -Z
  geo.rotateY(Math.PI);                                       // now points along +Z
  const body = new THREE.Mesh(geo, arrowMat); body.castShadow = true;
  const edge = new THREE.Mesh(geo, outline); edge.scale.setScalar(1.08);
  arrow.add(body, edge); arrow.userData.mat = arrowMat;
  scene.add(arrow);
  // light beacon over the current target, visible from far away
  beacon = new THREE.Mesh(new THREE.CylinderGeometry(0.9, 0.9, 40, 16, 1, true), new THREE.MeshBasicMaterial({ color: '#ffd27a', transparent: true, opacity: 0.28, depthWrite: false, side: THREE.DoubleSide, toneMapped: false }));
  beacon.position.y = 20; scene.add(beacon);
}

// ------------------------------------------------------------------ particles (sparkles, fireworks)
const sparks = [];
const sparkGeo = new THREE.SphereGeometry(0.12, 5, 4);
function burst(pos, color, n = 18, power = 6, life = 0.9) {
  for (let i = 0; i < n; i++) {
    const m = new THREE.Mesh(sparkGeo, new THREE.MeshBasicMaterial({ color, transparent: true, toneMapped: false }));
    m.position.copy(pos);
    const v = new THREE.Vector3(rand() - 0.5, rand() * 0.8 + 0.4, rand() - 0.5).normalize().multiplyScalar(power * (0.5 + rand()));
    scene.add(m); sparks.push({ m, v, life, max: life });
  }
}
const confettiBits = [];
const confettiGeo = new THREE.PlaneGeometry(0.28, 0.16);
function confetti(pos, n) {
  const cols = ['#ff8fb1', '#ffd27a', '#7fd1ff', '#b9f27c', '#c9a2ff', '#ff6b6b', '#ffffff'];
  for (let i = 0; i < n; i++) {
    const m = new THREE.Mesh(confettiGeo, new THREE.MeshBasicMaterial({ color: cols[i % cols.length], side: THREE.DoubleSide, toneMapped: false }));
    m.position.copy(pos);
    const v = new THREE.Vector3((rand() - 0.5) * 2, rand() * 1.2 + 0.6, (rand() - 0.5) * 2).normalize().multiplyScalar(8 + rand() * 10);
    scene.add(m); confettiBits.push({ m, v, spin: new THREE.Vector3(rand() * 8, rand() * 8, rand() * 8), life: 7 + rand() * 3 });
  }
}
const flights = [];
function flyToCake(candle) {
  const from = candle.mesh.position.clone().setY(1.5);
  flights.push({ obj: candle.mesh, from, t: 0, dur: 1.3 });
  candle.mesh.visible = true;
}
function updateFlights(dt) {
  for (let i = flights.length - 1; i >= 0; i--) {
    const f = flights[i]; f.t += dt / f.dur;
    const to = cakeTop();
    const k = Math.min(f.t, 1);
    const p = f.from.clone().lerp(to, k); p.y += Math.sin(k * Math.PI) * 14;
    f.obj.position.copy(p); f.obj.scale.setScalar(1.25 * (1 - k * 0.7));
    f.obj.rotation.y += dt * 10;
    if (f.t >= 1) {
      f.obj.visible = false; flights.splice(i, 1);
      const slot = cakeCandles.find((c) => !c.visible);
      if (slot) slot.visible = true;
      burst(to, '#ffd27a', 8, 3, 0.5);
    }
  }
  for (let i = confettiBits.length - 1; i >= 0; i--) {
    const c = confettiBits[i]; c.life -= dt;
    c.v.y -= 6 * dt; c.v.multiplyScalar(Math.exp(-1.6 * dt)); c.v.y = Math.max(c.v.y, -2.5);
    c.m.position.addScaledVector(c.v, dt);
    c.m.rotation.x += c.spin.x * dt; c.m.rotation.y += c.spin.y * dt; c.m.rotation.z += c.spin.z * dt;
    if (c.life <= 0 || c.m.position.y < -0.5) { scene.remove(c.m); c.m.material.dispose(); confettiBits.splice(i, 1); }
  }
}
function flyHudCandle() {
  const v = car.pos.clone().setY(1.5).project(camera);
  const el = document.createElement('div'); el.className = 'flyc'; el.textContent = '🕯';
  el.style.left = ((v.x + 1) / 2 * innerWidth) + 'px'; el.style.top = ((1 - v.y) / 2 * innerHeight) + 'px';
  document.body.appendChild(el);
  const r = $('candles').getBoundingClientRect();
  requestAnimationFrame(() => { el.style.left = (r.left + 22) + 'px'; el.style.top = (r.top + 18) + 'px'; el.style.transform = 'translate(-50%,-50%) scale(.5)'; el.style.opacity = '0.2'; });
  setTimeout(() => { el.remove(); $('candles').classList.add('pop'); setTimeout(() => $('candles').classList.remove('pop'), 250); }, 700);
}
function updateSparks(dt) {
  for (let i = sparks.length - 1; i >= 0; i--) {
    const s = sparks[i]; s.life -= dt;
    s.v.y -= 9 * dt; s.m.position.addScaledVector(s.v, dt);
    s.m.material.opacity = Math.max(0, s.life / s.max);
    if (s.life <= 0) { scene.remove(s.m); s.m.material.dispose(); sparks.splice(i, 1); }
  }
}

// ------------------------------------------------------------------ input
const keys = {};
addEventListener('keydown', (e) => {
  if (e.code.startsWith('Arrow') || e.code === 'Space') e.preventDefault();
  keys[e.code] = true;
  if (e.code === 'KeyH') honk();
  if ((e.code === 'Enter' || e.code === 'Space') && letterOpen) closeLetter();
  if ((e.code === 'Space' || e.code === 'Enter' || e.code === 'KeyE') && wishing) keys.Wish = true;
});
addEventListener('keyup', (e) => { keys[e.code] = false; if (e.code === 'Space' || e.code === 'Enter' || e.code === 'KeyE') keys.Wish = false; });
const stick = { active: false, id: null, ox: 0, oy: 0, x: 0, y: 0 };
const stickEl = $('stick'), baseEl = $('stickBase'), knobEl = $('stickKnob');
stickEl.addEventListener('pointerdown', (e) => {
  stick.active = true; stick.id = e.pointerId; stick.ox = e.clientX; stick.oy = e.clientY; stick.x = stick.y = 0;
  baseEl.style.left = e.clientX + 'px'; baseEl.style.top = e.clientY + 'px'; baseEl.classList.remove('hidden');
  stickEl.setPointerCapture(e.pointerId);
});
stickEl.addEventListener('pointermove', (e) => {
  if (!stick.active || e.pointerId !== stick.id) return;
  let dx = e.clientX - stick.ox, dy = e.clientY - stick.oy; const max = 60; const l = Math.hypot(dx, dy);
  if (l > max) { dx *= max / l; dy *= max / l; }
  stick.x = dx / max; stick.y = dy / max; knobEl.style.transform = `translate(${dx}px, ${dy}px)`;
});
const endStick = (e) => { if (e.pointerId !== stick.id) return; stick.active = false; stick.x = stick.y = 0; knobEl.style.transform = ''; baseEl.classList.add('hidden'); };
stickEl.addEventListener('pointerup', endStick); stickEl.addEventListener('pointercancel', endStick);
$('honk').addEventListener('pointerdown', (e) => { e.preventDefault(); honk(); });
document.querySelectorAll('#pad button').forEach((btn) => {
  const code = btn.dataset.key;
  const down = (e) => { e.preventDefault(); keys[code] = true; btn.classList.add('on'); btn.setPointerCapture?.(e.pointerId); };
  const up = () => { keys[code] = false; btn.classList.remove('on'); };
  btn.addEventListener('pointerdown', down); btn.addEventListener('pointerup', up); btn.addEventListener('pointercancel', up); btn.addEventListener('lostpointercapture', up);
});
let padOn = false;
function showControls(on) {
  const playing = started && !letterOpen && !wishing && !howtoOpen;
  $('pad').classList.toggle('hidden', !(on && playing && padOn));
  $('stick').classList.toggle('hidden', !(on && playing));
  $('honk').classList.toggle('hidden', !(on && playing));
}
$('padBtn').addEventListener('click', () => { padOn = !padOn; $('padBtn').classList.toggle('on', padOn); showControls(true); });

// ------------------------------------------------------------------ audio
let actx, engineOsc, engineGain, engineFilter, musicEl, muted = false;
function startAudio() {
  actx = new (window.AudioContext || window.webkitAudioContext)();
  engineOsc = actx.createOscillator(); engineOsc.type = 'sawtooth';
  engineFilter = actx.createBiquadFilter(); engineFilter.type = 'lowpass'; engineFilter.frequency.value = 400;
  engineGain = actx.createGain(); engineGain.gain.value = 0;
  engineOsc.connect(engineFilter).connect(engineGain).connect(actx.destination); engineOsc.start();
  musicEl = new Audio(songURL || 'audio/song.mp3'); musicEl.loop = true; musicEl.volume = 0.45;
  musicEl.onerror = () => { musicEl.onerror = null; musicEl.src = 'audio/music.mp3'; musicEl.volume = 0.3; musicEl.play().catch(() => {}); };
  musicEl.play().catch(() => {});
}
let musicPaused = false;
// ---- "Use my song": pick an audio file; it is kept in this browser (IndexedDB) for next time
let songURL = null;
function idb() { return new Promise((res, rej) => { try { const r = indexedDB.open('uncle-mo', 1); r.onupgradeneeded = () => r.result.createObjectStore('kv'); r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error); } catch (e) { rej(e); } }); }
async function saveSong(file) { try { const db = await idb(); db.transaction('kv', 'readwrite').objectStore('kv').put(file, 'song'); } catch (e) {} }
async function loadSong() { try { const db = await idb(); return await new Promise((res) => { const q = db.transaction('kv').objectStore('kv').get('song'); q.onsuccess = () => res(q.result || null); q.onerror = () => res(null); }); } catch (e) { return null; } }
function useSong(file) {
  songURL = URL.createObjectURL(file);
  $('songName').textContent = '🎵 ' + (file.name || 'Your song').replace(/\.[^.]+$/, '');
  if (musicEl) { musicEl.src = songURL; musicEl.volume = 0.45; if (!musicPaused && !muted) musicEl.play().catch(() => {}); }
}
$('songPick').addEventListener('change', (e) => { const f = e.target.files[0]; if (f) { useSong(f); saveSong(f); } });
loadSong().then((f) => { if (f) useSong(f); });
function pauseMusic() { musicPaused = true; musicEl?.pause(); }
function resumeMusic() { musicPaused = false; if (musicEl && !muted) musicEl.play().catch(() => {}); }
function blip(freqs, dur = 0.18, type = 'sine', vol = 0.08) {
  if (!actx || muted) return;
  const t = actx.currentTime;
  freqs.forEach((f, i) => {
    const o = actx.createOscillator(); const g = actx.createGain(); o.type = type; o.frequency.value = f;
    const st = t + i * dur * 0.6;
    g.gain.setValueAtTime(0.0001, st); g.gain.exponentialRampToValueAtTime(vol, st + 0.02); g.gain.exponentialRampToValueAtTime(0.0001, st + dur);
    o.connect(g).connect(actx.destination); o.start(st); o.stop(st + dur + 0.05);
  });
}
const honk = () => blip([392, 494], 0.35, 'square', 0.07);
const sfx = {
  candle: () => blip([880, 1320], 0.16, 'sine', 0.08),
  power: () => blip([523, 659, 784, 1047], 0.14, 'triangle', 0.09),
  bump: () => blip([110, 82], 0.2, 'square', 0.08),
  mud: () => blip([140], 0.25, 'sawtooth', 0.04),
  locked: () => blip([330, 262], 0.22, 'triangle', 0.08),
  letter: () => blip([659, 784, 988, 1319], 0.3, 'sine', 0.07),
  rise: () => blip([262, 330, 392, 523, 659, 784], 0.25, 'triangle', 0.07),
  cheer: () => blip([523, 659, 784, 1047, 1319, 1568], 0.18, 'square', 0.05),
};
$('mute').addEventListener('click', () => {
  muted = !muted; $('mute').textContent = muted ? '🔇' : '🔊';
  if (musicEl) musicEl.muted = muted;
  if (voiceEl) voiceEl.muted = muted;
  if (muted && 'speechSynthesis' in window) speechSynthesis.cancel();
});

// voice: her recording (audio/letters/<name>.mp3 or .m4a), else device voice
let voiceEl = null;
let onVoiceEnd = null;
function playVoice(name, text, onEnd = null) {
  onVoiceEnd = onEnd;
  stopVoice();
  const exts = ['mp3', 'm4a', 'wav'];
  let k = 0;
  const tryNext = () => {
    if (k >= exts.length) { return; }
    const a = new Audio(`audio/letters/${name}.${exts[k++]}`);
    voiceEl = a; a.muted = muted;
    a.onended = () => onVoiceEnd && onVoiceEnd();
    a.onerror = () => { if (voiceEl === a) tryNext(); };
    a.play().catch(() => { if (voiceEl === a && a.error) tryNext(); });
  };
  tryNext();
}
function ttsFallback(text) {
  if (!('speechSynthesis' in window) || muted) return;
  const u = new SpeechSynthesisUtterance(text);
  const vs = speechSynthesis.getVoices();
  u.voice = vs.find((v) => v.lang.startsWith('en') && /female|samantha|karen|serena|moira|zira|susan|libby|sonia/i.test(v.name)) || vs.find((v) => v.lang.startsWith('en')) || null;
  u.rate = 0.92; u.onend = () => onVoiceEnd && onVoiceEnd();
  speechSynthesis.speak(u);
}
function stopVoice() {
  if (voiceEl) { voiceEl.pause(); voiceEl = null; }
  if ('speechSynthesis' in window) speechSynthesis.cancel();
}

// ------------------------------------------------------------------ HUD / game state
let started = false, letterOpen = false, finale = false, howtoOpen = false;
let candleCount = 0, nextLetter = 0;
const power = { type: null, t: 0 };
let mudSlow = 0, toastT = 0;
const dots = $('dots');
LETTERS.forEach(() => dots.appendChild(document.createElement('span')));
function refreshHud() {
  [...dots.children].forEach((d, i) => d.classList.toggle('on', i < nextLetter));
  $('candleNum').textContent = `${candleCount} / ${CONFIG.age}`;
  $('candleFill').style.width = (candleCount / CONFIG.age * 100) + '%';
  let obj = '';
  if (cakeState === 'done' || finale) obj = 'Happy birthday! 🎉 Free drive';
  else if (cakeState === 'wishing') obj = 'Hold the button (or SPACE) to blow out the candles';
  else if (nextLetter >= LETTERS.length) {
    obj = candleCount < CONFIG.age ? `Final goal: collect all ${CONFIG.age} candles (${candleCount}/${CONFIG.age})` : 'Drive to the birthday cake 🎂';
  } else {
    const L = LETTERS[nextLetter];
    obj = `Collect candles — letter ${nextLetter + 1} opens at ${L.need} (${candleCount}/${L.need})`;
  }
  $('objective').textContent = obj;
}
function toast(msg, secs = 2.5) { const t = $('toast'); t.textContent = msg; t.classList.add('on'); toastT = secs; }

let letterMode = 'letter', letterScrollHeld = false;
$('letterText').addEventListener('pointerdown', () => { letterScrollHeld = true; });
$('letterText').addEventListener('wheel', () => { letterScrollHeld = true; });
function openLetter(i, mode = 'letter') {
  letterOpen = true; letterMode = mode; letterScrollHeld = false; sfx.letter();
  const L = mode === 'prayer' ? CONFIG.afterCandles : LETTERS[i];
  $('letterNum').textContent = mode === 'prayer' ? 'ON YOUR 39TH ❤️' : `LETTER ${i + 1} OF ${LETTERS.length + 1}`;
  $('letterTitle').textContent = '';
  $('letter').classList.toggle('noimg', !L.image);
  if (L.image) $('letterImg').src = L.image;
  $('letterSign').textContent = CONFIG.fromName ? `— ${CONFIG.fromName}` : '';
  $('letterNext').textContent = mode === 'prayer' ? 'Àṣẹ ❤️' : (i === LETTERS.length - 1 ? 'Find the cake ▸' : 'Keep driving ▸');
  pauseMusic();
  const box = $('letterText'); box.innerHTML = ''; box.scrollTop = 0;
  L.paragraphs.forEach((t, k) => { const p = document.createElement('p'); p.textContent = t; if (k === 0 && /^Dear /.test(t)) p.className = 'dear'; box.appendChild(p); });
  const el = $('letter'); el.classList.remove('hidden', 'show', 'opened');
  requestAnimationFrame(() => { el.classList.add('show'); setTimeout(() => el.classList.add('opened'), 900); });
  setTimeout(() => playVoice(mode === 'prayer' ? CONFIG.afterCandles.voice : `letter_${String(i + 1).padStart(2, '0')}`), 1300);
  showControls(false);
}
function maybeRaiseCake() {
  if (cakeState === 'hidden' && candleCount >= CONFIG.age && nextLetter >= LETTERS.length) {
    cakeState = 'rising'; cakeRiseT = 0; sfx.rise(); toast('The birthday cake is rising! 🎂 Follow the green arrow', 4);
  }
}
function closeLetter() {
  if (!letterOpen) return;
  stopVoice(); resumeMusic();
  const el = $('letter'); el.classList.remove('show');
  setTimeout(() => el.classList.add('hidden'), 500);
  letterOpen = false;
  setTimeout(() => showControls(true), 0);
  if (letterMode === 'prayer') { startFinale(); return; }
  if (mailboxes[nextLetter]) mailboxes[nextLetter].opened = true;
  nextLetter++;
  refreshHud();
  maybeRaiseCake();
}
$('letterNext').addEventListener('click', closeLetter);
$('howtoGo').addEventListener('click', () => { $('howto').classList.add('hidden'); howtoOpen = false; showControls(true); $('padBtn').classList.toggle('on', padOn); });
$('helpBtn').addEventListener('click', () => { $('howto').classList.remove('hidden'); howtoOpen = true; showControls(false); });

function startFinale() {
  finale = true; refreshHud();
  const name = CONFIG.heroName ? `, ${CONFIG.heroName}` : '';
  $('finaleTitle').textContent = `Happy 39th Birthday, Uncle Mo`;
  $('finaleText').textContent = CONFIG.finale;
  $('finale').classList.remove('hidden');
  requestAnimationFrame(() => $('finale').classList.add('show'));
  fireworksT = 16;
}
// ---- the wish
let wishHold = 0, wishing = false;
function startWish() {
  cakeState = 'wishing'; wishing = true; car.speed = 0;
  cakeCandles.forEach((c) => { c.visible = true; c.userData.flame.visible = true; });
  $('wish').classList.remove('hidden');
  showControls(false);
  toast('Make a wish… 🎂', 3); refreshHud();
}
function finishWish() {
  wishing = false; cakeState = 'done'; refreshHud();
  $('wish').classList.add('hidden');
  let k = 0;
  const blowOut = setInterval(() => {
    for (let n = 0; n < 4 && k < cakeCandles.length; n++, k++) {
      const c = cakeCandles[k]; c.userData.flame.visible = false;
      burst(c.getWorldPosition(new THREE.Vector3()).add(new THREE.Vector3(0, 1, 0)), '#dddddd', 3, 2, 0.6);
    }
    if (k >= cakeCandles.length) {
      clearInterval(blowOut);
      confetti(cakePlate.position.clone().add(new THREE.Vector3(0, 6, 0)), isTouch ? 260 : 420);
      sfx.cheer();
      setTimeout(() => openLetter(0, 'prayer'), 2600);
    }
  }, 60);
  setTimeout(() => showControls(true), 0);
}
const wishDown = (e) => { e?.preventDefault?.(); keys.Wish = true; };
const wishUp = () => { keys.Wish = false; };
$('wishBtn').addEventListener('pointerdown', wishDown);
$('wishBtn').addEventListener('pointerup', wishUp);
$('wishBtn').addEventListener('pointerleave', wishUp);
let fireworksT = 0;
$('finaleClose').addEventListener('click', () => { $('finale').classList.remove('show'); setTimeout(() => $('finale').classList.add('hidden'), 600); stopVoice(); });

$('start').addEventListener('click', () => {
  started = true;
  $('title').classList.add('hidden'); $('hud').classList.remove('hidden');
  if (isTouch) {
    document.documentElement.requestFullscreen?.().catch(() => {});
    screen.orientation?.lock?.('landscape').catch(() => {});
  }
  startAudio(); refreshHud();
  $('howto').classList.remove('hidden'); howtoOpen = true;
  if ('speechSynthesis' in window) speechSynthesis.speak(new SpeechSynthesisUtterance(''));
});

manager.onLoad = () => {
  buildTerrain(); buildGrass(); populate(); buildCar();
  car.pos.copy(spawn); car.prev.copy(spawn);
  camera.position.copy(spawn).add(CAM_OFFSET);
  $('loadbar').classList.add('hidden'); $('start').classList.remove('hidden');
  refreshHud();
  window.__ready = true;
  window.__debug = { car, mailboxes, candles, openLetter, closeLetter, get state() { return { candleCount, nextLetter, power: power.type }; }, setCandles: (n) => { candleCount = n; for (let i = 0; i < n && i < cakeCandles.length; i++) cakeCandles[i].visible = true; refreshHud(); maybeRaiseCake(); }, setLetter: (n) => { nextLetter = n; refreshHud(); }, get cakeState() { return cakeState; }, cakePos: () => cakePlate.position, wish: (on) => { keys.Wish = on; } };
};

// ------------------------------------------------------------------ loop
const clock = new THREE.Clock();
const camTarget = new THREE.Vector3();
let engineLevel = 0;
function tick() {
  const dt = Math.min(clock.getDelta(), 0.05);
  const t = clock.elapsedTime;
  grassTime.value = t;
  if (!map || !spawn) { renderer.render(scene, camera); requestAnimationFrame(tick); return; }

  // ---- input
  let throttle = 0, steer = 0;
  if (started && !letterOpen && !howtoOpen && !wishing) {
    if (keys.KeyW || keys.ArrowUp) throttle += 1;
    if (keys.KeyS || keys.ArrowDown) throttle -= 0.7;
    if (keys.KeyA || keys.ArrowLeft) steer += 1;
    if (keys.KeyD || keys.ArrowRight) steer -= 1;
    if (stick.active && Math.hypot(stick.x, stick.y) > 0.15) {
      const desired = Math.atan2(stick.x, stick.y);
      let diff = desired - car.heading; diff = Math.atan2(Math.sin(diff), Math.cos(diff));
      steer = THREE.MathUtils.clamp(diff * 2.2, -1, 1);
      throttle = Math.min(1, Math.hypot(stick.x, stick.y)) * (Math.abs(diff) > 2.4 ? 0.4 : 1);
    }
  }
  // ---- power-ups & surfaces
  if (power.t > 0) { power.t -= dt; if (power.t <= 0) { power.type = null; $('power').classList.remove('on'); } else { $('powerBar').style.width = (power.t / POWER[power.type].time * 100) + '%'; } }
  const turbo = power.type === 'turbo', shield = power.type === 'shield', magnet = power.type === 'magnet';
  shieldBubble && (shieldBubble.visible = shield);
  mudSlow = Math.max(0, mudSlow - dt);
  const wet = kind(car.pos.x, car.pos.z) === 'water';
  let maxSpeed = (keys.ShiftLeft || keys.ShiftRight ? 25 : 19) * (turbo ? 1.6 : 1) * (mudSlow > 0 && !shield ? 0.4 : 1) * (wet && !turbo ? 0.6 : 1);
  const accel = turbo ? 40 : 24;

  car.speed += throttle * accel * dt;
  car.speed -= car.speed * (throttle === 0 ? 1.6 : 0.6) * dt;
  if (car.speed > maxSpeed) car.speed = THREE.MathUtils.lerp(car.speed, maxSpeed, 0.15);
  car.speed = Math.max(car.speed, -8);
  car.steer = THREE.MathUtils.lerp(car.steer, steer, 1 - Math.exp(-16 * dt));
  const sp = car.speed;
  const factor = Math.abs(sp) < 1 ? 0.7 : THREE.MathUtils.clamp(Math.abs(sp) / 3, 0.7, 1) * Math.sign(sp);
  car.heading += car.steer * 2.6 * factor * dt + car.spin * dt;
  car.spin *= Math.exp(-4 * dt);
  car.prev.copy(car.pos);
  car.pos.x += Math.sin(car.heading) * car.speed * dt;
  car.pos.z += Math.cos(car.heading) * car.speed * dt;

  // water: you can drive through it — slower, with splashes
  const inWater = kind(car.pos.x, car.pos.z) === 'water';
  if (inWater && Math.abs(car.speed) > 3 && rand() < 0.5) burst(car.pos.clone().add(new THREE.Vector3((rand() - 0.5) * 3, 0, (rand() - 0.5) * 3)).setY(-0.3), '#cfeaff', 3, 4, 0.5);
  // keep inside the island area
  const edge = WORLD * 0.62; const rr = Math.hypot(car.pos.x, car.pos.z);
  if (rr > edge) { car.pos.x *= edge / rr; car.pos.z *= edge / rr; car.speed *= 0.5; }
  for (const c of colliders) {
    const dx = car.pos.x - c.x, dz = car.pos.z - c.z; const d = Math.hypot(dx, dz); const r = c.r + 1.4;
    if (d < r && d > 0.001) { car.pos.x = c.x + dx / d * r; car.pos.z = c.z + dz / d * r; car.speed *= 0.7; }
  }

  // ---- obstacles
  for (const o of obstacles) {
    if (o.knocked) {
      o.timer -= dt;
      o.vel.y -= 18 * dt; o.mesh.position.addScaledVector(o.vel, dt);
      if (o.mesh.position.y < 0) { o.mesh.position.y = 0; o.vel.multiplyScalar(0.5); o.vel.y *= -0.3; }
      o.mesh.rotation.x += o.spin * dt; o.mesh.rotation.z += o.spin * 0.7 * dt;
      if (o.timer < 1) o.mesh.scale.setScalar(Math.max(0.01, o.timer));
      if (o.timer <= 0) { o.knocked = false; o.mesh.position.copy(o.home); o.mesh.rotation.set(0, o.rot, 0); o.mesh.scale.setScalar(1); }
      continue;
    }
    const r = o.type === 'barrier' ? 2.3 : 1.7;
    if (Math.hypot(car.pos.x - o.pos.x, car.pos.z - o.pos.z) < r && started) {
      o.knocked = true; o.timer = 12;
      const dir = new THREE.Vector3(Math.sin(car.heading), 0, Math.cos(car.heading));
      o.vel.copy(dir).multiplyScalar(Math.max(6, Math.abs(car.speed)) * 0.9); o.vel.y = 7; o.spin = (rand() - 0.5) * 14;
      if (!shield) {
        car.speed *= o.type === 'cone' ? 0.55 : 0.25; car.spin = (rand() - 0.5) * 5; sfx.bump();
        if (o.type !== 'cone') toast('Bump! 💥', 1.2);
      } else { burst(o.mesh.position.clone().setY(1), '#7cf29a', 10, 5); blip([660], 0.1); }
    }
  }
  for (const m of muds) {
    if (Math.hypot(car.pos.x - m.pos.x, car.pos.z - m.pos.z) < m.r) {
      if (mudSlow <= 0 && !shield && Math.abs(car.speed) > 4) { sfx.mud(); toast('Mud! Slow going…', 1.2); }
      mudSlow = 0.5;
    }
  }
  // ---- power-ups
  for (const p of powerups) {
    if (p.timer > 0) { p.timer -= dt; if (p.timer <= 0) p.mesh.visible = true; continue; }
    p.mesh.children[0].rotation.y = t * 2; p.mesh.children[1].rotation.x = t * 1.5; p.mesh.children[0].position.y = 1.5 + Math.sin(t * 3) * 0.2;
    if (started && Math.hypot(car.pos.x - p.pos.x, car.pos.z - p.pos.z) < 2.6) {
      p.mesh.visible = false; p.timer = 25;
      power.type = p.type; power.t = POWER[p.type].time;
      $('powerLabel').textContent = POWER[p.type].label; $('power').style.borderColor = POWER[p.type].color; $('powerBar').style.background = POWER[p.type].color;
      $('power').classList.add('on'); sfx.power(); burst(p.pos.clone().setY(1.5), POWER[p.type].color, 24, 7);
      if (p.type === 'turbo') car.speed = Math.max(car.speed, 22);
    }
  }
  // ---- candles
  for (const c of candles) {
    if (c.taken) continue;
    const fl = c.mesh.userData.flame; fl.scale.set(1, 1 + Math.sin(t * 14 + c.phase) * 0.12, 1);
    c.mesh.position.y = 0.2 + Math.sin(t * 2 + c.phase) * 0.18; c.mesh.rotation.y = t * 0.8 + c.phase;
    const d = Math.hypot(car.pos.x - c.mesh.position.x, car.pos.z - c.mesh.position.z);
    if (magnet && d < 18) { c.mesh.position.x += (car.pos.x - c.mesh.position.x) * Math.min(1, 6 * dt); c.mesh.position.z += (car.pos.z - c.mesh.position.z) * Math.min(1, 6 * dt); }
    if (started && !wishing && d < 2.3 && candleCount < CONFIG.age) {
      c.taken = true; candleCount = Math.min(candleCount + 1, CONFIG.age); sfx.candle();
      if (c.mesh.userData.ring) c.mesh.userData.ring.visible = false;
      burst(c.mesh.position.clone().setY(1.3), '#ffcf5a', 12, 5);
      flyToCake(c); flyHudCandle();
      if (nextLetter < LETTERS.length && candleCount === LETTERS[nextLetter].need) { const li = nextLetter; toast(`✉ You unlocked letter ${li + 1}!`, 2); setTimeout(() => { if (!letterOpen && nextLetter === li) { car.speed = 0; openLetter(li); } }, 900); }
      if (candleCount === CONFIG.age) { candles.forEach((o) => { if (!o.taken) { o.taken = true; o.mesh.visible = false; } }); maybeRaiseCake(); }
      refreshHud();
    }
  }
  // ---- mailboxes (letters 1-9)
  let target = null, targetKind = '';
  mailboxes.forEach((mb, i) => {
    const isNext = i === nextLetter && !finale;
    const ready = isNext && candleCount >= LETTERS[i].need;
    mb.ring.material.opacity = ready ? 0.55 + Math.sin(t * 4) * 0.3 : 0;
    mb.flag.rotation.z = mb.opened ? -1.4 : (ready ? Math.sin(t * 6) * 0.25 : 0);
    mb.num.material.opacity = mb.opened ? 0.3 : (isNext ? 1 : 0.6);
    mb.group.visible = true;
    const d = Math.hypot(car.pos.x - mb.pos.x, car.pos.z - mb.pos.z);
    if (started && !letterOpen && isNext && d < 3.8) {
      if (ready) { car.speed = 0; openLetter(i); }
      else if (!mb.warned) { mb.warned = true; sfx.locked(); toast(`🔒 Collect ${LETTERS[i].need - candleCount} more candles first`, 2.5); }
    }
    if (d > 8) mb.warned = false;
  });
  // ---- the cake
  if (cakeState === 'rising') {
    cakeRiseT += dt / 3;
    cake.position.y = THREE.MathUtils.lerp(-7, 0, THREE.MathUtils.smoothstep(cakeRiseT, 0, 1));
    if (rand() < 0.5) burst(cakePlate.position.clone().add(new THREE.Vector3((rand() - 0.5) * 7, 0.5, (rand() - 0.5) * 7)), '#ffd27a', 2, 4, 0.7);
    if (cakeRiseT >= 1) { cakeState = 'ready'; refreshHud(); }
  }
  cakePlate.userData.sign.visible = cakeState === 'hidden';
  cakePlate.userData.sign.position.y = 3.2 + Math.sin(t * 2) * 0.2;
  const cakeDist = Math.hypot(car.pos.x - cakePlate.position.x, car.pos.z - cakePlate.position.z);
  if (cakeState === 'ready' && started && !letterOpen && cakeDist < 8) startWish();
  if (wishing) {
    wishHold = keys.Wish ? Math.min(1, wishHold + dt / 2.5) : Math.max(0, wishHold - dt * 0.4);
    $('wishFill').style.width = (wishHold * 100) + '%';
    cakeCandles.forEach((c, i) => c.userData.flame.scale.setScalar(1 + Math.sin(t * 16 + i) * 0.1 + (keys.Wish ? Math.sin(t * 30 + i) * 0.2 : 0)));
    if (wishHold >= 1) finishWish();
  }
  // ---- where to go next
  if (!finale && cakeState !== 'done') {
    const finalStage = nextLetter >= LETTERS.length;
    const quota = finalStage ? CONFIG.age : LETTERS[nextLetter].need;
    if (candleCount < quota) {
      let bd = Infinity;
      for (const c of candles) { if (c.taken) continue; const d = Math.hypot(c.pos.x - car.pos.x, c.pos.z - car.pos.z); if (d < bd) { bd = d; target = c.mesh.position; } }
      targetKind = 'candle';
    }
    else if (cakeState === 'ready' || cakeState === 'rising') { target = cakePlate.position; targetKind = 'cake'; }
  }
  if (arrow) {
    const show = !!target && started && !letterOpen && !wishing;
    arrow.visible = show; beacon.visible = show;
    if (target) {
      const dist = Math.hypot(target.x - car.pos.x, target.z - car.pos.z);
      const ang = Math.atan2(target.x - car.pos.x, target.z - car.pos.z);
      // floats well ahead of the car and glides on its own (it guides, it doesn't push)
      const reach = Math.min(9, Math.max(dist - 1, 3));
      const want = new THREE.Vector3(car.pos.x + Math.sin(ang) * reach, 4 + Math.sin(t * 2.5) * 0.25, car.pos.z + Math.cos(ang) * reach);
      if (!arrow.userData.placed) { arrow.position.copy(want); arrow.userData.placed = true; }
      arrow.position.lerp(want, 1 - Math.exp(-2.5 * dt));
      let dr = ang - arrow.rotation.y; dr = Math.atan2(Math.sin(dr), Math.cos(dr));
      arrow.rotation.y += dr * (1 - Math.exp(-4 * dt));
      arrow.scale.setScalar(dist < 8 ? 0.7 : 0.9);
      const col = { candle: '#ffd27a', mail: '#ff6f9c', cake: '#9cf06b' }[targetKind];
      arrow.userData.mat.color.set(col); arrow.userData.mat.emissive.set(col);
      beacon.material.color.set(col); beacon.position.x = target.x; beacon.position.z = target.z;
      beacon.material.opacity = THREE.MathUtils.clamp((dist - 6) / 20, 0, 0.32);
      const label = { candle: '🕯 Next candle', mail: `✉ Letter ${nextLetter + 1}`, cake: '🎂 The cake' }[targetKind];
      $('target').textContent = `${label} · ${Math.round(dist)} m`;
      $('target').style.borderColor = col;
      $('target').classList.remove('hidden');
    }
  }
  if (!target || !started) $('target').classList.add('hidden');
  updateFlights(dt);
  if (letterOpen && voiceEl && voiceEl.duration > 0 && !letterScrollHeld) { const box = $('letterText'); const target = (box.scrollHeight - box.clientHeight) * Math.min(1, voiceEl.currentTime / voiceEl.duration * 1.04); box.scrollTop += (target - box.scrollTop) * 0.08; }
  // ---- finale fireworks
  if (fireworksT > 0) {
    fireworksT -= dt;
    if (rand() < dt * 3) burst(cakePlate.position.clone().add(new THREE.Vector3((rand() - 0.5) * 30, 10 + rand() * 8, (rand() - 0.5) * 20)), ['#ff8fb1', '#ffd27a', '#7fd1ff', '#b9f27c', '#c9a2ff'][Math.floor(rand() * 5)], 40, 9, 1.6);
  }
  updateSparks(dt);
  if (toastT > 0) { toastT -= dt; if (toastT <= 0) $('toast').classList.remove('on'); }

  // ---- car visuals
  car.group.position.copy(car.pos);
  car.group.position.y = THREE.MathUtils.lerp(car.group.position.y, Math.max(terrainHeight(car.pos.x, car.pos.z), -0.55), 0.15);
  car.group.rotation.y = car.heading - Math.PI / 2;
  if (car.body) {
    car.body.rotation.x = THREE.MathUtils.lerp(car.body.rotation.x, -car.steer * Math.abs(car.speed) * 0.006, 0.2);
    car.body.rotation.z = THREE.MathUtils.lerp(car.body.rotation.z, throttle * 0.03, 0.1);
    car.body.position.y = 1.05 + Math.sin(t * 20) * 0.01 * Math.min(1, Math.abs(car.speed) / 10) + (mudSlow > 0 ? Math.sin(t * 30) * 0.03 : 0);
  }
  car.wheels.forEach((w) => { if (w.front) w.holder.rotation.y = car.steer * 0.45; });
  car.spinners.forEach((s) => { s.rotation.z -= car.speed * dt / 0.45; });
  if (turbo && rand() < 0.6) burst(car.pos.clone().add(new THREE.Vector3(-Math.sin(car.heading) * 2.2, 0.8, -Math.cos(car.heading) * 2.2)), '#ffb347', 2, 2, 0.4);

  // ---- engine
  if (actx && engineOsc) {
    engineLevel = THREE.MathUtils.lerp(engineLevel, Math.abs(car.speed) / 20, 0.1);
    engineOsc.frequency.value = 45 + engineLevel * 90 + (turbo ? 25 : 0);
    engineFilter.frequency.value = 250 + engineLevel * 900;
    engineGain.gain.value = muted || letterOpen ? 0 : 0.022 + engineLevel * 0.045;
  }

  // ---- lights & camera
  sun.position.set(car.pos.x - 25, 30, car.pos.z + 18); sun.target.position.copy(car.pos);
  water.material.color.setHSL(0.57, 0.85, 0.5 + Math.sin(t * 0.8) * 0.025);
  const look = Math.min(Math.abs(car.speed), 15) * 0.35;
  camTarget.set(car.pos.x + Math.sin(car.heading) * look, 0, car.pos.z + Math.cos(car.heading) * look);
  camera.position.lerp(camTarget.clone().add(CAM_OFFSET), 1 - Math.exp(-3 * dt));
  camera.lookAt(camera.position.clone().sub(CAM_OFFSET));
  sky.position.copy(camera.position);

  renderer.render(scene, camera);
  requestAnimationFrame(tick);
}
requestAnimationFrame(tick);

function onResize() {
  renderer.setSize(innerWidth, innerHeight);
  camera.aspect = innerWidth / innerHeight;
  camera.fov = camera.aspect < 1 ? 60 : (camera.aspect < 1.6 ? 44 : 38);
  camera.updateProjectionMatrix();
}
addEventListener('resize', onResize); onResize();
