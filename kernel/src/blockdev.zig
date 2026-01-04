//! Block Device

pub const InfoBlock = extern struct {
    sector_size: u16,
    sector_count: u64,
};
