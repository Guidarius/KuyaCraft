# Woodland cleanup sources

Generated frames live in ignored assets/generated/woodland; never paint those files.
Use tools/assets/woodland_edit.py to prepare an editable Aseprite workspace outside source,
then import validated edits here. Aseprite is optional for every automated build.

The importer stores changed color/mask PNG pairs and their editable .aseprite in
edits/<content-hash>/. It merges frame entries into manifest.json only after validating
the complete edit. Existing edit revisions remain intact.

Manifest format:

    {"sourceRevision":"<render revision>","frames":{
      "48/idle/S/1":{"color":"edits/<hash>/1-color.png","mask":"edits/<hash>/1-mask.png"}
    }}

Frame samples are one-based; clip names are idle, move, work. A source revision mismatch
stops the build before publication. Review against newly rendered frames, then explicitly
migrate the affected entries and revision. Never automatically relabel stale cleanup.

Keep exactly the color and mask layers and original frame order/canvas in Aseprite.
Mask red values 51/102/153/204/255 select the five team shades; zero means neutral.
G and B remain zero. Alpha must match the color layer and be only 0 or 255.
Changing silhouette requires changing alpha in both layers. Use the supplied palette;
team-colored pixels must match the corresponding blue palette shade.
