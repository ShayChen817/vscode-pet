# Final Generated-Asset Briefs

Mode: OpenAI built-in image generation, `stylized-concept` sprite production.

All five assets use one exact 5 columns x 5 rows layout. Rows are: five-frame idle; five-frame bicycle kick; point-self, transition, point-ground, SIU takeoff, SIU landing; two-frame Calma plus three-frame sleeping meditation; five-frame shirt grab, pull, overhead removal, roar, recovery. Every cell is full-body, centered on a common floor line, clean cel-shaded 2D game art, and free of text, logos, sponsors, trademarks, shadows, glow, chromatic aberration, or colored fringe.

## Purple Noodle master

Create a premium transparent Windows desktop-pet sprite sheet inspired by Ronaldo's 2016/17 purple-kit noodle-hair era. Use a generic royal-purple number 7 kit with white trim and no branding. Hair must be dense compact dark curls with separated gold-brown highlighted noodle strands and closely faded sides. Keep the same recognizable face, compact athletic chibi proportions, black outline, lighting, scale, and identity across all 25 sequential frames. The sleeping celebration must be upright with the head slightly back, eyes closed, and fingers overlapped across the upper chest, not a generic defensive arms-crossed pose. The background must contain true alpha; the technical cleanup pass removes all brown backing, purple aura, halo, bloom, RGB split, colored edge pixels, and drop shadow.

## Young Ronaldo

Use the Purple Noodle master as the exact action, camera, layout, proportion, and rendering anchor. Change only the era styling to a slightly leaner 2005-2007 young Ronaldo: tall wet-look spiky dark hair with multiple sharp blond/gold highlighted tips, youthful face and eyebrows, generic classic red number 7 shirt with white piping, white shorts, black socks with white top bands, and white boots. Preserve the complete 25-frame rig and use a leaner shirtless build in row five. No logos or brand marks.

## Juventus Half & Half

Use the master pose rig unchanged. Create a mature Juventus-era Ronaldo with a short dark brushed-back textured top, tight faded sides, no ponytail or bun, and a natural light-to-medium warm olive Mediterranean complexion with subtle healthy sun tan. The generic shirt is divided into exactly two solid vertical halves, white and black, with opposite-color sleeves and one thin muted-pink center seam; pair it with black shorts, black socks, and white boots. Preserve the authentic sleeping meditation and all 25 frames. No stripes, club crest, sponsor, manufacturer mark, stars, patches, or wordmarks.

## Portugal Euro Red

Use the master pose rig unchanged. Create a Euro-2016-era version with a clean short dark side-parted top, close fade, subtle hard part, and mature athletic build. Use a generic deep-red number 7 shirt with dark forest-green collar and cuff details, forest-green shorts, red socks, restrained gold numbering, and white boots. Preserve all 25 frames and the same face, floor line, outline, and lighting. No federation crest, tournament patch, sponsor, logo, or wordmark.

## White & Gold

Use the master pose rig unchanged. Create a 2011/12 white-and-gold-era version with a glossy jet-black sculpted spiky quiff, short sides, subtle side part, sleek powerful build, and generic brilliant-white number 7 kit with precise metallic-gold piping on collar, cuffs, side seams, shorts, socks, and a tiny boot accent. Gold is trim only, never glow. Preserve all 25 frames and remove all logos, sponsors, badges, wordmarks, and manufacturer patterns.

## Production cleanup

Each generated sheet is preserved as `assets\skins\<skin>\sheet-source.png`. `tools\build_animation_assets.py` removes the generated neutral checkerboard by connected-background segmentation, erodes contaminated edge pixels, applies a neutral near-black antialiased matte, groups connected body parts and detached footballs to their nearest animation cell, prevents cross-cell slicing, and emits 25 real-alpha PNG frames plus a preview and launcher icon.
