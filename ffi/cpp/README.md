ffi/cpp/
├── build_windows.bat           # Dedicated Windows one-click build script (outputs to run_win)
├── build_linux.sh              # Dedicated Linux one-click build script (outputs to run_linux)
├── run_win/                    # Windows runtime environment (ez_dbengine.dll + test executables)
├── run_linux/                  # Linux runtime environment (libez_dbengine.so + test executables)
├── CMakeLists.txt              # CMake build definition (aligned with run_* directories)
├── ez_dbengine.hpp             # C++ RAII header file
├── ez_dbengine.cpp             # C++ RAII wrapper implementation
├── ez_stress_master.cpp        # Stress test benchmark master program
└── relation_demo.cpp           # Relation view demonstration program