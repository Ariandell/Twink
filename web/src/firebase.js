import { initializeApp } from "firebase/app";
import { getAuth } from "firebase/auth";
import {
  getDatabase,
  ref,
  onValue,
  update,
  remove,
  runTransaction,
  push,
  serverTimestamp,
  increment,
} from "firebase/database";
import {
  entries,
  freshProgress,
  logicalDay,
  importRows,
  autoFolder,
} from "./domain";
// Firebase client identifiers are public configuration, not service account credentials.
const app = initializeApp({
  apiKey: "AIzaSyC5L2JlRmCrlq0Zyj1CIwbtd18eHHwkL3g",
  authDomain: "german-df0f0.firebaseapp.com",
  projectId: "german-df0f0",
  databaseURL: "https://german-df0f0-default-rtdb.firebaseio.com",
  appId: "1:1027440373390:web:e00b47c3e68e61083023df",
});
export const auth = getAuth(app),
  database = getDatabase(app);
export function repository(uid) {
  const root = `users/${uid}`;
  return {
    subscribe: (ok, error) =>
      onValue(ref(database, root), (s) => ok(s.val() || {}), error),
    patch: (changes) => update(ref(database, root), changes),
    delete: (path) => remove(ref(database, `${root}/${path}`)),
    async save(kind, data) {
      if (data.id) {
        const { id, ...fields } = data;
        await update(ref(database, `${root}/${kind}/${id}`), fields);
        return id;
      }
      let assigned;
      await runTransaction(
        ref(database, `${root}/${kind}`),
        (raw) => {
          const records = Object.fromEntries(
            entries(raw).map((w) => [w.id, w]),
          );
          const max = Math.max(
            kind === "idioms" ? 99999 : 0,
            ...Object.keys(records).map((k) => Number(k) || 0),
          );
          assigned = String(max + 1);
          if (kind === "words" && Number(assigned) >= 100000)
            throw new Error("Досягнуто ліміт ID слів старого формату");
          records[assigned] = {
            ...data,
            folder: data.folder || autoFolder(Object.values(records)),
            id: assigned,
            progress_global: freshProgress(),
            ...(kind === "words"
              ? {
                  progress_groups: freshProgress(),
                  interval: 0,
                  nextDate: Date.now(),
                }
              : {}),
          };
          return records;
        },
        { applyLocally: false },
      );
      return assigned;
    },
    async importRecords(kind, rows) {
      await runTransaction(
        ref(database, `${root}/${kind}`),
        (raw) => {
          const existing = Object.fromEntries(
            entries(raw).map((w) => [w.id, w]),
          );
          return { ...existing, ...importRows(rows, kind, existing).updates };
        },
        { applyLocally: false },
      );
    },
    progress: (kind, id, p) =>
      update(ref(database, `${root}/${kind}/${id}`), {
        progress_global: p,
        ...(kind === "words"
          ? { interval: p?.interval || 0, nextDate: p?.nextDate || 0 }
          : {}),
      }),
    time: (seconds) =>
      update(ref(database, `${root}/stats/daily`), {
        [logicalDay()]: increment(seconds),
      }),
    folder: (name, kind) =>
      update(ref(database, `${root}/folderMeta/${name}`), {
        type: kind === "idioms" ? "idioms" : "words",
        createdAt: serverTimestamp(),
      }),
    newKey: () => push(ref(database, root)).key,
  };
}
