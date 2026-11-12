import 'package:lumii_quest/core/icons/app_icons.dart';

/// Image-generation styles available when Ishtar is in image mode. Each tag
/// carries a detailed style prompt that is prepended to the user's request
/// before it is sent to the image generator.
enum ImageTag {
  anime(
    icon: AppIcons.sparkles,
    label: 'Anime',
    description: 'Anime-style illustration.',
    prompt:
        'Anime-style illustration with clean cel shading, bold expressive '
        'line art, large detailed eyes with glossy highlights, and vibrant '
        'saturated colors. Use a dynamic, energetic composition with strong '
        'silhouettes and a clear focal point. Render it as a high-quality 2D '
        'animation still: crisp edges, smooth gradients, layered soft shadows '
        'and rim light, and a detailed painted background that supports the '
        'subject. Keep proportions stylized but consistent, with expressive '
        'facial features and hair that flows naturally. Add glossy highlights '
        'on skin and eyes and a tasteful bloom around bright areas. Avoid '
        'photorealism, 3D rendering, and messy sketch lines. No text, no '
        'watermark, no border, no signature, no extra fingers or limbs.',
  ),
  fantasy(
    icon: AppIcons.broomSparkles,
    label: 'Fantasy',
    description: 'Mythical worlds and creatures.',
    prompt:
        'Epic fantasy concept art with a sense of scale and wonder: dramatic '
        'landscapes, ancient castles, towering mountains, enchanted forests, '
        'and mythical creatures rendered with rich painterly detail. Use '
        'dramatic, atmospheric lighting — golden-hour sunlight, god rays '
        'through clouds, or glowing magical light sources — to create depth '
        'and mood. Employ a rich, cinematic color palette with deep shadows '
        'and luminous highlights. Compose the scene with a clear foreground, '
        'midground and background so it feels grand and immersive. Render in '
        'high resolution, oil-painting-like digital art with visible texture '
        'and fine detail. Avoid modern or futuristic elements, and keep the '
        'mood magical and adventurous. No text, no watermark, no border, no '
        'signature, no extra limbs or fingers.',
  ),
  spicy(
    icon: AppIcons.pepperChilli,
    label: 'Spicy',
    description: 'Suggestive, tasteful romance.',
    prompt:
        'Suggestive romantic artwork that is tasteful, teasing and elegant '
        'rather than explicit: emphasise mood, atmosphere and suggestion over '
        'detail. Use soft, flattering lighting with warm tones, gentle '
        'gradients, and a shallow depth of field that draws attention to the '
        'subject. Compose the figure elegantly, with a confident yet refined '
        'pose, delicate fabric, and implied rather than graphic anatomy. Keep '
        'the styling classy and editorial, like high-end fashion or romantic '
        'illustration, with rich but subtle colors. Absolutely avoid explicit '
        'nudity, graphic anatomy, or vulgar framing — keep it sensual and '
        'alluring while remaining in good taste. No text, no watermark, no '
        'border, no signature.',
  ),
  realistic(
    icon: AppIcons.flower,
    label: 'Realistic',
    description: 'Photorealistic images.',
    prompt:
        'Photorealistic image with true-to-life lighting, accurate textures, '
        'and natural colors. Simulate a high-end full-frame camera: sharp '
        'focus on the subject, a soft creamy shallow depth of field, '
        'realistic lens rendering and fine grain, and balanced exposure. Pay '
        'close attention to skin pores, hair strands, fabric weave, '
        'reflections and micro-details so nothing looks painted or CGI. Use '
        'natural or convincingly realistic studio lighting with accurate '
        'shadows and ambient occlusion. Keep the composition grounded and '
        'believable, with correct anatomical proportions, perspective and '
        'scale. Avoid cartoonish, stylized or oversaturated rendering. No '
        'text, no watermark, no border, no signature, no extra fingers or '
        'limbs.',
  ),
  traditional(
    icon: AppIcons.feather,
    label: 'Traditional',
    description: 'Classical painting and drawing.',
    prompt:
        'Classical traditional art in the style of a museum oil painting: '
        'visible brush strokes, rich layered glazes, and a muted historical '
        'palette of earth tones, deep shadows and warm highlights. Use '
        'dramatic chiaroscuro lighting and a balanced, formal composition '
        'inspired by the old masters. Render canvas texture and impasto where '
        'it adds depth, and keep edges soft and painterly rather than crisp '
        'or digital. Aim for a timeless, hand-painted look with subtle color '
        'variation and gentle gradients. Avoid photographic sharpness, modern '
        'neon colors, and flat digital shading. No text, no watermark, no '
        'border, no signature.',
  ),
  cyberpunk(
    icon: AppIcons.brainCircuit,
    label: 'Cyberpunk',
    description: 'Neon-drenched sci-fi.',
    prompt:
        'Cyberpunk scene set in a rain-slick, neon-lit futuristic city at '
        'night: glowing holograms, dense signage, towering megastructures, '
        'and moody atmospheric haze. Use high contrast between deep shadows '
        'and saturated neon accents (cyan, magenta, amber), with reflective '
        'wet surfaces and volumetric fog. Add cybernetic details, cables, '
        'drones and futuristic vehicles to sell the setting, and light the '
        'subject with mixed colored rim lights. Render in a cinematic, '
        'film-noir style with a slight film grain. Keep the mood gritty, '
        'high-tech and atmospheric, and avoid clean, sterile or daytime '
        'looks. No text, no watermark, no border, no signature, no extra '
        'fingers or limbs.',
  ),
  watercolor(
    icon: AppIcons.palette,
    label: 'Watercolor',
    description: 'Soft watercolor painting.',
    prompt:
        'Soft watercolor painting with translucent, layered washes that blend '
        'gently into one another. Use a light, airy palette with delicate '
        'color gradients, visible paper texture, and soft feathered edges '
        'where pigment bleeds naturally. Let areas of white paper show '
        'through for highlights, and keep the composition light, delicate and '
        'slightly impressionistic. Avoid hard outlines, heavy opacity and '
        'digital gradients — the look should be hand-painted on textured '
        'paper. Emphasize negative space and a calm, ethereal mood. No text, '
        'no watermark, no border, no signature.',
  ),
  pixelArt(
    icon: AppIcons.square,
    label: 'Pixel Art',
    description: 'Retro pixel-art sprites.',
    prompt:
        'Retro pixel art in a crisp 16-bit video-game style: clean, '
        'grid-aligned pixels with no anti-aliasing or blur. Use a limited, '
        'well-chosen color palette with clear light and shadow steps, and '
        'readable silhouettes. Render small but expressive details — eyes, '
        'highlights and texture — within a modest resolution, with deliberate '
        'dithering where gradients are needed. Keep the composition charming, '
        'readable and nostalgic, like a classic SNES or arcade sprite scene. '
        'Avoid smooth gradients, photorealism and modern rendering. No text, '
        'no watermark, no border, no signature.',
  ),
  threeD(
    icon: AppIcons.box,
    label: '3D Render',
    description: '3D rendered scenes.',
    prompt:
        'High-end 3D render with physically-based rendering: realistic PBR '
        'materials, accurate reflections, subsurface scattering where '
        'relevant, and volumetric lighting. Use a cinematic camera angle with '
        'shallow depth of field, soft shadows and ambient occlusion for '
        'depth. Render in octane/Cycles quality with smooth surfaces, fine '
        'geometric detail and polished textures. Light the scene with a clear '
        'key light, rim light and fill light for a professional studio look. '
        'Keep geometry clean and proportions correct, and avoid flat or toon '
        'shading. No text, no watermark, no border, no signature, no extra '
        'fingers or limbs.',
  ),
  retro(
    icon: AppIcons.pacMan,
    label: 'Retro',
    description: 'Vintage film photography.',
    prompt:
        'Vintage film photograph look, like a grainy 35mm snapshot from the '
        '1970s-80s: faded, slightly warm colors, soft halation around '
        'highlights, gentle light leaks, and visible film grain. Use a '
        'nostalgic, candid composition with natural lighting and a slight '
        'softness or motion blur that suggests an old camera. Add subtle '
        'dust, scratches or vignetting for authenticity, and keep the color '
        'palette muted and analog rather than digital. The mood should feel '
        'warm, nostalgic and documentary-like. Avoid modern crispness, high '
        'dynamic range and oversaturation. No text, no watermark, no border, '
        'no signature.',
  ),
  abstract(
    icon: AppIcons.torus,
    label: 'Abstract',
    description: 'Abstract and experimental.',
    prompt:
        'Abstract artwork built from bold geometric shapes, sweeping curves '
        'and expressive color fields. Combine flat planes of color with '
        'experimental textures, gradients and gestural marks to create visual '
        'rhythm and tension. Use a confident, limited-to-mid color palette '
        'with intentional contrast, and leave generous negative space so the '
        'composition feels minimal yet striking. Prioritize balance, motion '
        'and emotion over representational accuracy — no recognizable '
        'objects, faces or text. Keep the result gallery-worthy, modern and '
        'clean. No text, no watermark, no border, no signature.',
  ),
  portrait(
    icon: AppIcons.squareUserRound,
    label: 'Portrait',
    description: 'Character portraits.',
    prompt:
        'High-quality character portrait with a detailed, expressive face as '
        'the focal point. Use studio-quality lighting — a soft key light with '
        'gentle rim and fill — to sculpt the features, and keep the '
        'background softly blurred so nothing distracts from the subject. '
        'Render realistic skin texture, natural hair, expressive eyes and a '
        'believable, subtle expression with correct anatomical proportions. '
        'Compose the shot elegantly, with the eyes near the upper third and a '
        'clean, flattering crop. Choose a cohesive color grade and keep the '
        'mood clear and intentional. No text, no watermark, no border, no '
        'signature, no extra fingers or limbs.',
  );

  const ImageTag({
    required this.icon,
    required this.label,
    required this.description,
    required this.prompt,
  });

  final String icon;
  final String label;
  final String description;
  final String prompt;
}
