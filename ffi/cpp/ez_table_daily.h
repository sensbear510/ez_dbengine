#pragma once
#include "ez_def.h"

/**
 * DAILY_RECORD Structure
 * Precisely aligned to 128 bytes to match the engine's physical stride requirements.
 * Uses 4-byte packing to ensure consistent memory offsets across different platforms.
 */
#pragma pack(push, 4) 
typedef struct {
    /* --- [A] String Segment (Total: 60 Bytes) --- */
    ez_utf8  date[10];           /* [00] Date in ISO 8601 format: YYYY-MM-DD */ 
    ez_utf8  code[12];           /* [12] Securities Code (e.g., Stock Ticker) */
    ez_utf8  name[36];           /* [24] Securities Name (UTF-8 encoded) */

    /* --- [B] Numeric Segment (Total: 64 Bytes) --- */
    u32   trade_volume;       /* [60] Total shares traded */ 
    f64   trade_amount;       /* [68] Total trade monetary amount (U64) */    
    f32   open;               /* [72] Opening price (Scaled x100) */ 
    f32   high;               /* [76] Highest price (Scaled x100) */ 
    f32   low;                /* [80] Lowest price (Scaled x100) */ 
    f32   close;              /* [84] Closing price (Scaled x100) */ 
    f32   diff;               /* [88] Price difference/change */ 
    u32   trade_count;        /* [92] Total number of transactions */     
    /**
     * Optional/Reserved Fields (Legacy/Extended Meta):
     * buy_vol, buy_pri, sell_vol, sell_pri, pe_ratio, yield_rate, pbr_ratio
     * Currently omitted but maintained in documentation for physical stride alignment.
     */

} DAILY_RECORD;
#pragma pack(pop)

/**
 * Physical Verification:
 * Ensures the structure size aligns with the engine's minimum 128-byte record block.
 */
//ez_static_assert(sizeof(DAILY_RECORD) == 128, "Physical Alignment Failure: DAILY_RECORD must be exactly 128 bytes!");