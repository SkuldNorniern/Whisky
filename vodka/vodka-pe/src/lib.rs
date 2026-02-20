use std::fs;
use std::path::Path;

fn read_u16_le(bytes: &[u8], offset: usize) -> Option<u16> {
    let slice = bytes.get(offset..offset + 2)?;
    Some(u16::from_le_bytes([slice[0], slice[1]]))
}

fn read_u32_le(bytes: &[u8], offset: usize) -> Option<u32> {
    let slice = bytes.get(offset..offset + 4)?;
    Some(u32::from_le_bytes([slice[0], slice[1], slice[2], slice[3]]))
}

pub fn inspect_pe_bytes(bytes: &[u8]) -> Option<(u16, u16, u32)> {
    if bytes.len() < 0x40 {
        return None;
    }

    let pe_offset = read_u32_le(bytes, 0x3C)? as usize;
    if bytes.get(pe_offset..pe_offset + 4)? != b"PE\0\0" {
        return None;
    }

    let coff_offset = pe_offset + 4;
    let machine = read_u16_le(bytes, coff_offset)?;
    let optional_size = read_u16_le(bytes, coff_offset + 16)? as usize;
    let optional_offset = coff_offset + 20;

    if optional_size < 0x46 {
        return None;
    }

    let magic = read_u16_le(bytes, optional_offset)?;
    if magic != 0x10B && magic != 0x20B {
        return None;
    }

    let entry_point_rva = read_u32_le(bytes, optional_offset + 0x10)?;
    let subsystem = read_u16_le(bytes, optional_offset + 0x44)?;

    Some((machine, subsystem, entry_point_rva))
}

pub fn inspect_pe_path(path: &Path) -> Option<(u16, u16, u32)> {
    let bytes = fs::read(path).ok()?;
    inspect_pe_bytes(&bytes)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn build_minimal_pe() -> Vec<u8> {
        let mut bytes = vec![0u8; 0x200];

        bytes[0] = b'M';
        bytes[1] = b'Z';

        let pe_offset: u32 = 0x80;
        bytes[0x3C..0x40].copy_from_slice(&pe_offset.to_le_bytes());

        bytes[0x80..0x84].copy_from_slice(b"PE\0\0");

        let coff = 0x84;
        bytes[coff..coff + 2].copy_from_slice(&0x8664u16.to_le_bytes());
        bytes[coff + 16..coff + 18].copy_from_slice(&0x00F0u16.to_le_bytes());

        let optional = coff + 20;
        bytes[optional..optional + 2].copy_from_slice(&0x20Bu16.to_le_bytes());
        bytes[optional + 0x10..optional + 0x14].copy_from_slice(&0x12345678u32.to_le_bytes());
        bytes[optional + 0x44..optional + 0x46].copy_from_slice(&2u16.to_le_bytes());

        bytes
    }

    #[test]
    fn parses_valid_pe() {
        let pe = build_minimal_pe();
        let parsed = inspect_pe_bytes(&pe);
        assert_eq!(parsed, Some((0x8664, 2, 0x12345678)));
    }

    #[test]
    fn rejects_invalid_signature() {
        let mut pe = build_minimal_pe();
        pe[0x80] = b'X';
        assert!(inspect_pe_bytes(&pe).is_none());
    }
}
