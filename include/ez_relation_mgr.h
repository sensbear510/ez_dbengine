#pragma once

#include "ez_engine.h"

#define EZ_ERL_MAGIC 0x004C5245 /* Magic Identifier: 'ERL\0' */

/* ===================================================================== */
/* 1. PUBLIC DECLARATIVE DESCRIPTORS                                    */
/* ===================================================================== */

/** Field projection descriptor */
typedef struct {
    u16     ebf_index;                  /* Target EBF index in h_ebf_array */
    ez_char field_name[EZ_FILED_NAME_SIZE]; /* Original field name (52B) */
    ez_char alias_name[EZ_FILED_NAME_SIZE]; /* View alias field name (52B) */
} EZ_RL_NODE_DESC;

/** Foreign key link descriptor (Supports Single and Composite keys) */
typedef struct {
    u16     parent_ebf_index;           /* Parent EBF handle index in h_ebf_array */
    u16     child_ebf_index;            /* Child EBF handle index in h_ebf_array */
    u8      fk_field_count;             /* Key field count (1 for Single, 2~8 for Composite) */
    u16     parent_fk_offsets[8];       /* Offsets of FK fields in Parent Payload */
    u16     parent_fk_lens[8];          /* Byte lengths of FK fields in Parent Payload */
    ez_char child_tag_name[48];         /* Target Child EDX index tag name */
} EZ_RL_LINK_DESC;

/** One-shot declarative descriptor for spawning a Relation View */
typedef struct {
    const ez_char*        relation_name; /* Relation View Identifier */
    EZ_RL_JOIN_MODE       join_mode;     /* EZ_RL_JOIN_LEFT or EZ_RL_JOIN_INNER */
    const u64*            h_ebf_array;   /* Array of active EBF handles */
    u16                   ebf_count;     /* Count of bound EBF tables */
    const EZ_RL_NODE_DESC* nodes;        /* Array of field projections */
    u16                   node_count;    /* Count of view fields */
    const EZ_RL_LINK_DESC* links;        /* Array of relation links */
    u16                   link_count;    /* Count of relation links */
} EZ_RL_VIEW_DESC;

/** Header layout stored at the beginning of an .ERL file */
typedef struct {
    u32     magic;                  /* File magic identifier (EZ_ERL_MAGIC) */
    u16     version;                /* File format version (e.g. 1) */
    u16     join_mode;              /* EZ_RL_JOIN_LEFT or EZ_RL_JOIN_INNER */
    u16     node_count;             /* Count of EZ_RL_NODE_DESC projection items */
    u16     link_count;             /* Count of EZ_RL_LINK_DESC relation links */
    ez_char relation_name[64];      /* Relation View Name string */
} EZ_ERL_FILE_HEADER;

/* ===================================================================== */
/* 2. PUBLIC HIGH-LEVEL SYMMETRICAL LIFECYCLE APIS                       */
/* ===================================================================== */

/** Initialize global Relation Manager subsystem */
EZ_API EZ_STATUS ez_rl_mgr_init(void);

/** Cleanup global Relation Manager subsystem */
EZ_API EZ_STATUS ez_rl_mgr_cleanup(void);

/** One-Shot Declarative Builder: Audits geometry & registers handle */
EZ_API u64       ez_rl_build_view(const EZ_RL_VIEW_DESC* desc);

/** Symmetrical Destructor for ez_rl_build_view */
EZ_API EZ_STATUS ez_rl_destroy_view(const u64 h_rel);

/** Backward compatibility alias macro for ez_rl_destroy_view */
#define ez_rl_unregister(h_rel) ez_rl_destroy_view(h_rel)

/* ===================================================================== */
/* 3. SUBSYSTEM INTERNAL LOOKUP & QUERY APIS                             */
/* ===================================================================== */

/** Register relation table instance into global handle map */
EZ_API u64       ez_rl_register(void* rel);

/** Internal fast lookup function for active relation table context */
EZ_API void*     _ez_get_relation_table(const u64 h_rel);

/** Fetch stitched payload record vector from relation view */
EZ_API EZ_STATUS ez_rl_get_record_vector(EZ_RELATION_TABLE* rel, u8* out_buffer, u32 request_count, u32* actual_count);

/** Export view layout definition struct to an .ERL binary file */
EZ_API EZ_STATUS ez_rl_save_view_file(const EZ_RL_VIEW_DESC* desc, const ez_char* erl_path);

/** Import .ERL file and spawn active relation handle dynamically */
EZ_API u64       ez_rl_load_view_file(const ez_char* erl_path, const u64* h_ebf_array, u16 ebf_count);