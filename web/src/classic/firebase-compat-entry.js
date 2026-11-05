import firebase from "firebase/compat/app";
import "firebase/compat/auth";
import "firebase/compat/database";
import "./native-recognition";
import "./layout-navigation";
import { createDemoFirebase } from "./demo-store";
const requested = new URLSearchParams(location.search).get("demo");
if (requested === "1") {
  sessionStorage.setItem("twink-classic-demo", "1");
  sessionStorage.removeItem("twink-classic-demo-signed-out");
}
if (requested === "0") {
  sessionStorage.removeItem("twink-classic-demo");
  sessionStorage.removeItem("twink-classic-demo-signed-out");
}
window.firebase =
  sessionStorage.getItem("twink-classic-demo") === "1"
    ? createDemoFirebase(firebase)
    : firebase;
