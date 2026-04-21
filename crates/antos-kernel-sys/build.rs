use std::env;
use std::path::PathBuf;

fn main() {
    let headers = std::fs::read_dir("../../include/antk")
        .expect("Failed to read include directory")
        .filter_map(|entry| {
            let entry = entry.expect("Failed to read directory entry");
            let path = entry.path();
            if path.extension().and_then(|ext| ext.to_str()) == Some("h") {
                Some(path)
            } else {
                None
            }
        });

    println!("cargo:rerun-if-changed=../../include/antk");

    let mut builder = bindgen::Builder::default()
        .use_core()
        .generate_cstr(true)
        .default_enum_style(bindgen::EnumVariation::Rust {
            non_exhaustive: true,
        })
        .clang_arg("-ffreestanding");

    for header in headers{
        builder = builder.header(header.to_str().expect("Failed to convert header path to string"));
    }

    let bindings = builder
        .generate()
        .expect("Unable to generate bindings");

    // Write the bindings to the $OUT_DIR/bindings.rs file.
    let out_path = PathBuf::from(env::var("OUT_DIR").unwrap());
    bindings
        .write_to_file(out_path.join("bindings.rs"))
        .expect("Couldn't write bindings!");


}
