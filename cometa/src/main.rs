fn main() {
    if let Err(error) = cometa::run() {
        eprintln!("Cometa: {error}");
        std::process::exit(1);
    }
}
