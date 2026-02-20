use std::ffi::CStr;
use std::os::raw::c_char;
use std::path::PathBuf;
use std::ptr;

fn c_path_to_path(path: *const c_char) -> Option<PathBuf> {
    if path.is_null() {
        return None;
    }

    let c_str = unsafe { CStr::from_ptr(path) };
    Some(PathBuf::from(c_str.to_string_lossy().into_owned()))
}

fn inspect_path(path: *const c_char) -> Option<(u16, u16, u32)> {
    let path = c_path_to_path(path)?;
    vodka_pe::inspect_pe_path(&path)
}

#[no_mangle]
pub extern "C" fn vodka_pe_inspect(
    path: *const c_char,
    machine: *mut u16,
    subsystem: *mut u16,
    entry_point_rva: *mut u32,
) -> bool {
    let result = std::panic::catch_unwind(|| inspect_path(path));
    let Some((machine_value, subsystem_value, entry_point_value)) = result.ok().flatten() else {
        return false;
    };

    unsafe {
        if !machine.is_null() {
            *machine = machine_value;
        }
        if !subsystem.is_null() {
            *subsystem = subsystem_value;
        }
        if !entry_point_rva.is_null() {
            *entry_point_rva = entry_point_value;
        }
    }

    true
}

#[no_mangle]
pub extern "C" fn vodka_pe_validate_file(path: *const c_char) -> bool {
    vodka_pe_inspect(path, ptr::null_mut(), ptr::null_mut(), ptr::null_mut())
}

#[no_mangle]
pub extern "C" fn vodka_pe_extract_header(
    path: *const c_char,
    machine: *mut u16,
    subsystem: *mut u16,
    entry_point_rva: *mut u32,
) -> bool {
    vodka_pe_inspect(path, machine, subsystem, entry_point_rva)
}

#[no_mangle]
pub extern "C" fn whisky_rust_pe_validate_file(path: *const c_char) -> bool {
    vodka_pe_validate_file(path)
}

#[no_mangle]
pub extern "C" fn whisky_rust_pe_extract_header(
    path: *const c_char,
    machine: *mut u16,
    subsystem: *mut u16,
    entry_point_rva: *mut u32,
) -> bool {
    vodka_pe_extract_header(path, machine, subsystem, entry_point_rva)
}
