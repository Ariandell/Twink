// In-memory Firebase-compatible adapter for explicit ?demo=1 previews only.
// It never connects to the real user's database.
export function createDemoFirebase(real, storage = globalThis.sessionStorage) {
  const now = Date.now(),
    day = 86400000;
  const progress = (score) => ({
    interval: 0,
    nextDate: now - 1000,
    state: "new",
    isActive: score >= 10,
    is_ideal: score >= 10,
    excellentStreak: score,
  });
  const records = [
    [
      "1",
      "der Augenblick",
      "мгновение, момент",
      "",
      "Ein kurzer Moment.",
      "Genieße den Augenblick.",
      "Наслаждайтесь моментом.",
      "Папка 1",
      0,
    ],
    [
      "2",
      "entdecken",
      "обнаруживать, открывать",
      "entdeckte, hat entdeckt",
      "etwas Neues finden",
      "Wir entdecken jeden Tag etwas Neues.",
      "Мы каждый день открываем что-то новое.",
      "Папка 1",
      3,
    ],
    [
      "3",
      "die Möglichkeit",
      "возможность",
      "",
      "",
      "Es gibt viele Möglichkeiten.",
      "Существует много возможностей.",
      "Папка 1",
      9,
    ],
    [
      "4",
      "sich erinnern",
      "помнить, вспоминать",
      "erinnerte sich, hat sich erinnert",
      "sich an etwas erinnern",
      "Ich erinnere mich an diesen Tag.",
      "Я помню этот день.",
      "Папка 1",
      1.5,
    ],
    [
      "5",
      "die Entscheidung, -en",
      "решение",
      "",
      "eine Entscheidung treffen",
      "Das war eine gute Entscheidung.",
      "Это было хорошее решение.",
      "Папка 2",
      10,
    ],
  ];
  const words = Object.fromEntries(
    records.map(
      ([id, word, translation, info1, info2, ex1, ex2, folder, score]) => [
        id,
        {
          id,
          word,
          translation,
          info1,
          info2,
          ex1,
          ex2,
          folder,
          frequency: 4,
          interval: 0,
          nextDate: now - 1000,
          progress_global: progress(score),
          progress_groups: progress(0),
        },
      ],
    ),
  );
  let tree;
  try {
    tree = JSON.parse(storage.getItem("twink-classic-demo-data") || "null");
  } catch {}
  tree ||= {
    users: {
      demo: {
        nickname: "Пользователь",
        words,
        idioms: {
          100000: {
            id: "100000",
            idiom: "Daumen drücken",
            translation: "держать кулаки",
            meaning: "Желать кому-то удачи",
            info: "Разговорное выражение",
            example: "Ich drücke dir die Daumen!",
            folder: "Идиомы",
            progress_global: progress(0),
          },
        },
        folderMeta: {
          "Папка 1": { type: "words", createdAt: now - day },
          "Папка 2": { type: "words", createdAt: now },
        },
        settings: {
          study: {
            audio: false,
            audioWord: true,
            audioInfo1: true,
            audioInfo2: true,
            audioEx1: false,
            audioEx2: false,
            audioTranslation: true,
            examples: true,
            showWord: true,
            showInfo1: true,
            showInfo2: true,
            showEx1: true,
            showEx2: true,
            showProgress: true,
            showStatTotal: true,
            showStatDue: true,
            showStatToday: true,
            masterAudio: true,
            studyMode: "long",
          },
        },
        stats: {
          daily: {
            [new Date(now - 6 * 3600000).toISOString().slice(0, 10)]: 480,
            [new Date(now - day - 6 * 3600000).toISOString().slice(0, 10)]: 720,
          },
        },
      },
    },
  };
  const listeners = new Set(),
    authListeners = new Set();
  let uid = storage.getItem("twink-classic-demo-signed-out") ? null : "demo",
    serial = 0;
  const clone = (v) => (v === undefined ? null : JSON.parse(JSON.stringify(v)));
  const parts = (p) =>
    String(p || "")
      .split("/")
      .filter(Boolean);
  const read = (p) => parts(p).reduce((v, k) => v?.[k], tree) ?? null;
  const resolve = (value, current) =>
    value?.[".sv"] === "timestamp"
      ? Date.now()
      : value?.[".sv"]?.increment !== undefined
        ? (Number(current) || 0) + value[".sv"].increment
        : value;
  function write(path, value) {
    const keys = parts(path);
    if (!keys.length) {
      tree = value || {};
      return;
    }
    let obj = tree;
    for (const key of keys.slice(0, -1)) obj = obj[key] ??= {};
    const key = keys.at(-1);
    value = resolve(value, obj[key]);
    if (value === null) delete obj[key];
    else obj[key] = clone(value);
  }
  const snapshot = (path) => ({
    key: parts(path).at(-1) || null,
    val: () => clone(read(path)),
    exists: () => read(path) !== null,
    child: (key) => snapshot([path, key].filter(Boolean).join("/")),
    numChildren: () => Object.values(read(path) || {}).filter(Boolean).length,
    forEach: (fn) => {
      for (const key of Object.keys(read(path) || {})) {
        if (fn(snapshot(`${path}/${key}`)) === true) return true;
      }
      return false;
    },
  });
  function emit() {
    storage.setItem("twink-classic-demo-data", JSON.stringify(tree));
    for (const l of [...listeners]) {
      const value = JSON.stringify(read(l.path));
      if (value === l.last) continue;
      l.last = value;
      queueMicrotask(() => {
        if (listeners.has(l)) l.callback(snapshot(l.path));
      });
    }
  }
  function ref(path = "") {
    return {
      key: parts(path).at(-1) || null,
      child: (key) => ref([path, key].filter(Boolean).join("/")),
      on: (event, callback) => {
        const l = { path, callback, last: JSON.stringify(read(path)) };
        listeners.add(l);
        queueMicrotask(() => {
          if (listeners.has(l)) callback(snapshot(path));
        });
        return callback;
      },
      off: (event, callback) => {
        for (const l of listeners)
          if (l.path === path && (!callback || callback === l.callback))
            listeners.delete(l);
      },
      once: async () => snapshot(path),
      get: async () => snapshot(path),
      set: async (value) => {
        write(path, value);
        emit();
      },
      update: async (changes) => {
        for (const [key, value] of Object.entries(changes))
          write([path, key].filter(Boolean).join("/"), value);
        emit();
      },
      remove: async () => {
        write(path, null);
        emit();
      },
      transaction: async (fn, complete) => {
        const value = fn(clone(read(path)));
        const committed = value !== undefined;
        if (committed) {
          write(path, value);
          emit();
        }
        const snap = snapshot(path);
        complete?.(null, committed, snap);
        return { committed, snapshot: snap };
      },
      push: (value) => {
        const next = ref(`${path}/demo_${++serial}`);
        if (value !== undefined) next.set(value);
        return next;
      },
    };
  }
  const user = () =>
    uid
      ? {
          uid,
          email: "demo@example.com",
          metadata: { creationTime: new Date(now - 60 * day).toISOString() },
          updateEmail: async () => {},
          updatePassword: async () => {},
          delete: async () => {
            uid = null;
            authEmit();
          },
        }
      : null;
  function authEmit() {
    for (const fn of authListeners) setTimeout(() => fn(user()), 0);
  }
  const auth = {
    get currentUser() {
      return user();
    },
    onAuthStateChanged: (fn) => {
      authListeners.add(fn);
      const run = () => setTimeout(() => fn(user()), 0);
      if (document.readyState === "loading")
        document.addEventListener("DOMContentLoaded", run, { once: true });
      else run();
      return () => authListeners.delete(fn);
    },
    signInWithEmailAndPassword: async () => {
      uid = "demo";
      storage.removeItem("twink-classic-demo-signed-out");
      authEmit();
      return { user: user() };
    },
    createUserWithEmailAndPassword: async () => {
      uid = "demo";
      storage.removeItem("twink-classic-demo-signed-out");
      authEmit();
      return { user: user() };
    },
    signOut: async () => {
      uid = null;
      storage.setItem("twink-classic-demo-signed-out", "1");
      authEmit();
    },
    sendPasswordResetEmail: async () => {},
  };
  const db = () => ({ ref });
  db.ServerValue = {
    TIMESTAMP: { ".sv": "timestamp" },
    increment: (n) => ({ ".sv": { increment: n } }),
  };
  return {
    initializeApp: () => ({}),
    auth: () => auth,
    database: db,
    get apps() {
      return [{}];
    },
  };
}
