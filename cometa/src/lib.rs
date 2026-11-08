mod model;
mod render;
mod window;

pub fn run() -> Result<(), Box<dyn std::error::Error>> {
    if let Some(path) = std::env::args()
        .skip(1)
        .find_map(|a| a.strip_prefix("--capture=").map(str::to_owned))
    {
        return render::capture(&path);
    }
    window::run()
}

#[cfg(target_os = "android")]
#[unsafe(no_mangle)]
pub fn android_main(app: android_activity::AndroidApp) {
    if let Err(error) = window::run_android(app) {
        eprintln!("Cometa: {error}");
    }
}
