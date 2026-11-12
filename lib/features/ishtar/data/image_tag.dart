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
        'Anime style: clean cel shading, bold outlines, expressive eyes, '
        'vibrant saturated colors, dynamic composition. High-quality 2D '
        'animation still, detailed background, glossy highlights. No text, '
        'no watermark, no border.',
  ),
  fantasy(
    icon: AppIcons.broomSparkles,
    label: 'Fantasy',
    description: 'Mythical worlds and creatures.',
    prompt:
        'Fantasy art: epic mythical scenery, dragons, castles, enchanted '
        'forests, dramatic lighting, rich painterly detail, high-resolution '
        'concept-art quality. No text, no watermark, no border.',
  ),
  spicy(
    icon: AppIcons.pepperChilli,
    label: 'Spicy',
    description: 'Suggestive, tasteful romance.',
    prompt:
        'Suggestive romantic art: tasteful, teasing, elegant and atmospheric, '
        'soft lighting, flattering composition. Keep it sensual but classy, '
        'no explicit nudity, no text, no watermark, no border.',
  ),
  realistic(
    icon: AppIcons.flower,
    label: 'Realistic',
    description: 'Photorealistic images.',
    prompt:
        'Photorealistic image: natural lighting, sharp focus, true-to-life '
        'textures and skin, realistic colors, shallow depth of field, shot on '
        'a high-end camera. No text, no watermark, no border.',
  ),
  traditional(
    icon: AppIcons.feather,
    label: 'Traditional',
    description: 'Classical painting and drawing.',
    prompt:
        'Traditional art: classical oil painting, visible brush strokes, muted '
        'historical palette, dramatic chiaroscuro, museum-quality composition. '
        'No text, no watermark, no border.',
  ),
  cyberpunk(
    icon: AppIcons.brainCircuit,
    label: 'Cyberpunk',
    description: 'Neon-drenched sci-fi.',
    prompt:
        'Cyberpunk: neon-lit futuristic city, rain-slick streets, holograms, '
        'cybernetic details, high contrast, cinematic sci-fi atmosphere. '
        'No text, no watermark, no border.',
  ),
  watercolor(
    icon: AppIcons.palette,
    label: 'Watercolor',
    description: 'Soft watercolor painting.',
    prompt:
        'Watercolor painting: soft translucent washes, gentle color blending, '
        'delicate paper texture, airy and light composition. No text, no '
        'watermark, no border.',
  ),
  pixelArt(
    icon: AppIcons.square,
    label: 'Pixel Art',
    description: 'Retro pixel-art sprites.',
    prompt:
        'Pixel art: crisp retro 16-bit sprites, limited color palette, clean '
        'grid-aligned pixels, charming video-game aesthetic. No text, no '
        'watermark, no border.',
  ),
  threeD(
    icon: AppIcons.box,
    label: '3D Render',
    description: '3D rendered scenes.',
    prompt:
        '3D render: smooth PBR materials, volumetric lighting, octane-render '
        'quality, realistic reflections, high detail, cinematic camera angle. '
        'No text, no watermark, no border.',
  ),
  retro(
    icon: AppIcons.pacMan,
    label: 'Retro',
    description: 'Vintage film photography.',
    prompt:
        'Vintage film photography: grainy 35mm film, faded colors, soft '
        'halation, nostalgic 1970s-80s atmosphere, light leaks. No text, no '
        'watermark, no border.',
  ),
  abstract(
    icon: AppIcons.torus,
    label: 'Abstract',
    description: 'Abstract and experimental.',
    prompt:
        'Abstract art: bold shapes, geometric forms, expressive color fields, '
        'experimental textures, minimalist yet striking composition. No text, '
        'no watermark, no border.',
  ),
  portrait(
    icon: AppIcons.squareUserRound,
    label: 'Portrait',
    description: 'Character portraits.',
    prompt:
        'Character portrait: detailed face, expressive features, studio '
        'lighting, sharp focus on the subject, softly blurred background, high '
        'quality. No text, no watermark, no border.',
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
