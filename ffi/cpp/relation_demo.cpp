/* =================================================================================
 * 📁 FILE: relation_demo.cpp
 * ---------------------------------------------------------------------------------
 * C++ Stateless Singleton & Explicit Handle Relation Subsystem Demo
 * =================================================================================
 */

#include <iostream>
#include <vector>
#include "ez_dbengine.hpp"

int main() {
    // Acquire persistent engine singleton instance
    ez::EzDBEngine& engine = ez::EzDBEngine::get_instance();

    // 1. Initialize global Relation Subsystem
    engine.relation_mgr_init();

    try {
        // 2. Open physical EBF tables and obtain WorkArea Handles (stateless dispatch without instantiating objects)
        u64 hCustomer = engine.use("customer.ebf");
        u64 hOrders   = engine.use("orders.ebf");

        u64 ebfs[] = { hCustomer, hOrders };

        // 3. Define view field projection nodes (Field Projections)
        EZ_RL_NODE_DESC nodes[] = {
            { 0, "CUST_ID",  "CUSTOMER_ID"  },
            { 0, "NAME",     "CUSTOMER_NAME"},
            { 1, "ORDER_NO", "ORDER_NUMBER" },
            { 1, "AMOUNT",   "ORDER_AMOUNT" }
        };

        // 4. Define foreign key geometric links (Foreign Key Links)
        EZ_RL_LINK_DESC links[] = {
            {
                0,                          // Parent EBF Index in ebfs array
                1,                          // Child EBF Index in ebfs array
                1,                          // Foreign Key Field Count
                { 0 },                      // Parent FK Field Offsets in payload
                { 10 },                     // Parent FK Field Lengths in bytes
                "TAG_CUST_ID"               // Target Child EDX Index Tag Name
            }
        };

        // 5. Assemble declarative view descriptor (Declarative View Descriptor)
        EZ_RL_VIEW_DESC view_desc{};
        view_desc.relation_name = "CustomerOrdersView";
        view_desc.join_mode     = EZ_RL_JOIN_LEFT; // EZ_RL_JOIN_LEFT or EZ_RL_JOIN_INNER
        view_desc.h_ebf_array   = ebfs;
        view_desc.ebf_count     = 2;
        view_desc.nodes         = nodes;
        view_desc.node_count    = 4;
        view_desc.links         = links;
        view_desc.link_count    = 1;

        // 6. Build relation view and obtain Relation Handle (h_rel)
        u64 hRel = engine.relation_build_view(view_desc);

        if (hRel != 0) {
            std::cout << "Relation View built successfully! Handle: " << hRel << std::endl;

            // 7. Export relation structural layout to binary .ERL file
            engine.relation_save_view_file(view_desc, "customer_orders.erl");

            // 8. Retrieve stitched record vector data
            EZ_RELATION_TABLE* pRelTable = static_cast<EZ_RELATION_TABLE*>(engine.relation_get_table(hRel));
            if (pRelTable) {
                uint8_t buffer[1024] = {0};
                uint32_t actualCount = 0;
                if (engine.relation_get_record_vector(pRelTable, buffer, 10, &actualCount)) {
                    std::cout << "Successfully fetched " << actualCount << " stitched records!" << std::endl;
                }
            }

            // 9. Destroy relation view resources
            engine.relation_destroy_view(hRel);
        }

        // 10. Sequentially release underlying WorkArea Handles
        engine.close(hCustomer);
        engine.close(hOrders);

    } catch (const std::exception& e) {
        std::cerr << "Exception: " << e.what() << std::endl;
    }

    // 11. Clean up Relation Subsystem
    engine.relation_mgr_cleanup();
    return 0;
}