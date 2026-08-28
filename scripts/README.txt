Vertex Hub Phase 3

1. Copy phase3_initialize_canonical_knowledge.ps1 to:
   G:\Vertex_Project\Development\vertex_studio_ai\scripts\

2. Copy build_vertex_hub_public_v3.ps1 to:
   G:\Vertex_Project\Development\vertex_studio_ai\scripts\

3. Run:
   pwsh -ExecutionPolicy Bypass -File .\scripts\phase3_initialize_canonical_knowledge.ps1

4. Then run:
   pwsh -ExecutionPolicy Bypass -File .\scripts\build_vertex_hub_public_v3.ps1

This creates:
VertexHub\content\
VertexHub\data\
VertexHub\site\

No database is used.
