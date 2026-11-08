fn main() {
    // Android cannot load a library with unresolved C++ runtime symbols. Make
    // this a link error rather than shipping an APK that fails in NativeActivity.
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("android") {
        println!("cargo:rustc-link-arg=-Wl,--no-undefined");
    }
}
