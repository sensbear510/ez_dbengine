// ffi/rust/build.rs
fn main() {
    let target_os = std::env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();

    println!("cargo:rustc-link-search=native=.");
    println!("cargo:rustc-link-search=native=run_win");
    println!("cargo:rustc-link-search=native=run_linux");
    println!("cargo:rustc-link-search=native=../../build_win/bin/Release");
    println!("cargo:rustc-link-search=native=../../build_win/lib/Release");
    println!("cargo:rustc-link-search=native=../../build_win/bin");
    println!("cargo:rustc-link-search=native=../../build_win/lib");
    println!("cargo:rustc-link-search=native=../../build_win");
    println!("cargo:rustc-link-search=native=../../build_linux/lib");
    println!("cargo:rustc-link-search=native=../../build_linux");

    if target_os == "windows" {
        println!("cargo:rustc-link-lib=dylib=ez_dbengine");
    } else {
        println!("cargo:rustc-link-lib=dylib=ez_dbengine");
        // Linux 下加入 rpath，執行時優先在執行檔同目錄尋找 .so
        println!("cargo:rustc-link-arg=-Wl,-rpath,$ORIGIN");
    }
}