# Copy this file to library_setup.local.tcl and edit it for your environment.
# library_setup.local.tcl is intentionally ignored by git.

# Standard-cell Liberty .db used for mapping.
set target_library_files [list \
    "/path/to/your/standard_cell_typical.db" \
]

# Additional .db files needed only for linking, such as memory macros.
# Leave this as an empty list if the design does not need extra macro libraries.
set extra_link_library_files [list]
# Example:
# lappend extra_link_library_files "/path/to/your/memory_macro.db"
