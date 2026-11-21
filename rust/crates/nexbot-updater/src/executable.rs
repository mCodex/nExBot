use std::io::{self, Read, Seek, SeekFrom};

use crate::UpdateError;

#[derive(Clone, Copy)]
pub(crate) enum NativeFormat {
    Elf(u16),
    Pe(u16),
    Mach(u32),
}

impl NativeFormat {
    pub(crate) fn for_target(target: &str) -> Option<Self> {
        match target {
            "x86_64-unknown-linux-gnu" | "x86_64-unknown-linux-musl" => Some(Self::Elf(62)),
            "aarch64-unknown-linux-gnu" | "aarch64-unknown-linux-musl" => Some(Self::Elf(183)),
            "x86_64-pc-windows-msvc" | "x86_64-pc-windows-gnu" => Some(Self::Pe(0x8664)),
            "aarch64-pc-windows-msvc" => Some(Self::Pe(0xaa64)),
            "x86_64-apple-darwin" => Some(Self::Mach(0x01000007)),
            "aarch64-apple-darwin" => Some(Self::Mach(0x0100000c)),
            _ => None,
        }
    }

    pub(crate) fn check(self, mut artifact: impl Read + Seek) -> Result<(), UpdateError> {
        artifact.rewind()?;
        let mut header = [0; 64];
        read_header(&mut artifact, &mut header)?;

        let valid = match self {
            Self::Elf(machine) => {
                &header[..7] == b"\x7fELF\x02\x01\x01"
                    && matches!(&header[16..18], [2 | 3, 0])
                    && header[18..20] == machine.to_le_bytes()
            }
            Self::Pe(machine) => {
                let offset = u32::from_le_bytes([header[60], header[61], header[62], header[63]]);
                if &header[..2] != b"MZ" || !(64..=1024 * 1024).contains(&offset) {
                    return Err(UpdateError::Integrity);
                }
                artifact.seek(SeekFrom::Start(offset.into()))?;
                read_header(&mut artifact, &mut header[..26])?;
                &header[..4] == b"PE\0\0"
                    && header[4..6] == machine.to_le_bytes()
                    && header[22] & 0x02 != 0
                    && header[23] & 0x20 == 0
                    && header[24..26] == 0x20bu16.to_le_bytes()
            }
            Self::Mach(cpu) => {
                header[..4] == 0xfeedfacfu32.to_le_bytes()
                    && header[4..8] == cpu.to_le_bytes()
                    && header[12..16] == 2u32.to_le_bytes()
            }
        };

        if !valid {
            return Err(UpdateError::Integrity);
        }
        Ok(())
    }
}

fn read_header(mut artifact: impl Read, header: &mut [u8]) -> Result<(), UpdateError> {
    artifact.read_exact(header).map_err(|error| {
        if error.kind() == io::ErrorKind::UnexpectedEof {
            UpdateError::Integrity
        } else {
            error.into()
        }
    })
}
