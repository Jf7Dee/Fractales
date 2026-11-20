// Ressource de version Windows gravée dans fractal_kernel.dll : visible dans les propriétés du fichier et dans la
// fenêtre « À propos » de Fractales. La version vient de Cargo.toml.
use std::env;
use std::fs;
use std::path::PathBuf;

fn main() {
    if env::var("CARGO_CFG_TARGET_OS").as_deref() != Ok("windows") {
        return;
    }
    let version = env::var("CARGO_PKG_VERSION").unwrap();
    let major = env::var("CARGO_PKG_VERSION_MAJOR").unwrap();
    let minor = env::var("CARGO_PKG_VERSION_MINOR").unwrap();
    let patch = env::var("CARGO_PKG_VERSION_PATCH").unwrap();
    let rc = format!(
        r#"1 VERSIONINFO
FILEVERSION {major},{minor},{patch},0
PRODUCTVERSION {major},{minor},{patch},0
FILEOS 0x40004
FILETYPE 0x2
BEGIN
  BLOCK "StringFileInfo"
  BEGIN
    BLOCK "040C04B0"
    BEGIN
      VALUE "FileDescription", "Noyau de calcul de Fractales"
      VALUE "FileVersion", "{version}"
      VALUE "InternalName", "fractal_kernel"
      VALUE "OriginalFilename", "fractal_kernel.dll"
      VALUE "ProductName", "Fractales"
      VALUE "ProductVersion", "{version}"
    END
  END
  BLOCK "VarFileInfo"
  BEGIN
    VALUE "Translation", 0x40C, 1200
  END
END
"#
    );
    let path = PathBuf::from(env::var("OUT_DIR").unwrap()).join("version.rc");
    fs::write(&path, rc).unwrap();
    // compile_for_everything : compile() ne lie la ressource qu'aux exécutables, pas à une cdylib
    let _ = embed_resource::compile_for_everything(&path, embed_resource::NONE);
}
