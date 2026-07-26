use font_kit::handle::Handle;
use font_kit::source::SystemSource;
use std::collections::BTreeMap;
use std::ffi::{CString, c_char};
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::ptr;

struct FontRecord {
    label: CString,
    path: CString,
}

pub struct FontList {
    fonts: Vec<FontRecord>,
}

fn c_string(value: String) -> CString {
    CString::new(value.replace('\0', "")).expect("interior NUL bytes were removed")
}

fn enumerate_fonts() -> Result<FontList, font_kit::error::SelectionError> {
    let source = SystemSource::new();
    let mut by_path = BTreeMap::new();

    for family_name in source.all_families()? {
        let family = match source.select_family_by_name(&family_name) {
            Ok(family) => family,
            Err(_) => continue,
        };
        for handle in family.fonts() {
            if let Handle::Path { path, .. } = handle {
                let path_text = path.to_string_lossy().into_owned();
                by_path
                    .entry(path_text)
                    .and_modify(|existing: &mut String| {
                        if family_name < *existing {
                            *existing = family_name.clone();
                        }
                    })
                    .or_insert_with(|| family_name.clone());
            }
        }
    }

    let mut fonts: Vec<_> = by_path
        .into_iter()
        .map(|(path, label)| FontRecord {
            label: c_string(label),
            path: c_string(path),
        })
        .collect();
    fonts.sort_by(|a, b| {
        a.label
            .as_bytes()
            .cmp(b.label.as_bytes())
            .then_with(|| a.path.as_bytes().cmp(b.path.as_bytes()))
    });
    Ok(FontList { fonts })
}

#[unsafe(no_mangle)]
pub extern "C" fn lanlu_font_list_create() -> *mut FontList {
    catch_unwind(AssertUnwindSafe(enumerate_fonts))
        .ok()
        .and_then(Result::ok)
        .map_or(ptr::null_mut(), |fonts| Box::into_raw(Box::new(fonts)))
}

#[unsafe(no_mangle)]
/// # Safety
/// `list` must be null or a live pointer returned by `lanlu_font_list_create`.
pub unsafe extern "C" fn lanlu_font_list_count(list: *const FontList) -> usize {
    if list.is_null() {
        return 0;
    }
    unsafe { (*list).fonts.len() }
}

#[unsafe(no_mangle)]
/// # Safety
/// `list` must be null or a live pointer returned by `lanlu_font_list_create`.
pub unsafe extern "C" fn lanlu_font_list_label(
    list: *const FontList,
    index: usize,
) -> *const c_char {
    if list.is_null() {
        return ptr::null();
    }
    unsafe {
        let fonts = &(*list).fonts;
        fonts
            .get(index)
            .map_or(ptr::null(), |font| font.label.as_ptr())
    }
}

#[unsafe(no_mangle)]
/// # Safety
/// `list` must be null or a live pointer returned by `lanlu_font_list_create`.
pub unsafe extern "C" fn lanlu_font_list_path(
    list: *const FontList,
    index: usize,
) -> *const c_char {
    if list.is_null() {
        return ptr::null();
    }
    unsafe {
        let fonts = &(*list).fonts;
        fonts
            .get(index)
            .map_or(ptr::null(), |font| font.path.as_ptr())
    }
}

#[unsafe(no_mangle)]
/// # Safety
/// `list` must be null or a live pointer returned by `lanlu_font_list_create` that has not been destroyed.
pub unsafe extern "C" fn lanlu_font_list_destroy(list: *mut FontList) {
    if !list.is_null() {
        unsafe { drop(Box::from_raw(list)) };
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn enumerates_platform_fonts_with_valid_c_strings() {
        let fonts = enumerate_fonts().expect("font-kit should enumerate the platform source");
        assert!(!fonts.fonts.is_empty());
        assert!(
            fonts.fonts.iter().all(|font| {
                !font.label.as_bytes().is_empty() && !font.path.as_bytes().is_empty()
            })
        );
        let harmony: Vec<_> = fonts
            .fonts
            .iter()
            .filter(|font| font.label.to_string_lossy().contains("HarmonyOS Sans"))
            .map(|font| font.label.to_string_lossy().into_owned())
            .collect();
        eprintln!("HarmonyOS font-kit families: {harmony:?}");
    }

    #[test]
    fn c_abi_handles_null_and_out_of_range_inputs() {
        assert_eq!(unsafe { lanlu_font_list_count(ptr::null()) }, 0);
        assert!(unsafe { lanlu_font_list_label(ptr::null(), 0) }.is_null());
        assert!(unsafe { lanlu_font_list_path(ptr::null(), 0) }.is_null());
        unsafe { lanlu_font_list_destroy(ptr::null_mut()) };

        let list = lanlu_font_list_create();
        assert!(!list.is_null());
        let count = unsafe { lanlu_font_list_count(list) };
        assert!(unsafe { lanlu_font_list_label(list, count) }.is_null());
        assert!(unsafe { lanlu_font_list_path(list, count) }.is_null());
        unsafe { lanlu_font_list_destroy(list) };
    }
}
