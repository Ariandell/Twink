import React, { useRef } from "react";
import { createRoot } from "react-dom/client";
import "./classic-shell.css";

function Twink() {
  const frame = useRef(null);
  const demo = new URLSearchParams(location.search).get("demo") === "1";
  return (
    <iframe
      ref={frame}
      className="twink-original"
      title="WordyTwink"
      src={`./classic/index.html?demo=${demo ? "1" : "0"}`}
      allow="autoplay; microphone; clipboard-read; clipboard-write"
      onLoad={() => {
        const title = frame.current?.contentDocument?.title;
        if (title) document.title = title;
      }}
    />
  );
}
createRoot(document.getElementById("root")).render(<Twink />);
if (import.meta.env.PROD && "serviceWorker" in navigator)
  window.addEventListener("load", () =>
    navigator.serviceWorker.register("./sw.js").catch(() => {}),
  );
