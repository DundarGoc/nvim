-- 'Minischeme' color scheme
-- Derived from base16 (https://github.com/chriskempson/base16) and mini16
-- palette generator
local use_cterm, palette

-- Dark palette is an output of 'MiniBase16.mini_palette':
-- - Background '#1e2634' (LCh(uv) = 15-10-250)
-- - Foreground '#e2ea7c' (Lch(uv) = 90-70-90)
-- - Accent chroma 70
if vim.o.background == 'dark' then
  palette = {
    base00 = '#1e2634',
    base01 = '#414753',
    base02 = '#656b76',
    base03 = '#8c919c',
    base04 = '#d5dd6e',
    base05 = '#e2ea7c',
    base06 = '#eff78a',
    base07 = '#fcff98',
    base08 = '#ffd1a5',
    base09 = '#c97f4d',
    base0A = '#4da340',
    base0B = '#a4f69b',
    base0C = '#c671cb',
    base0D = '#5bf5ff',
    base0E = '#ffc6ff',
    base0F = '#00a3c2',
  }
  use_cterm = {
    base00 = 235,
    base01 = 238,
    base02 = 242,
    base03 = 246,
    base04 = 185,
    base05 = 186,
    base06 = 228,
    base07 = 228,
    base08 = 223,
    base09 = 173,
    base0A = 71,
    base0B = 156,
    base0C = 170,
    base0D = 87,
    base0E = 225,
    base0F = 37,
  }
end

-- Dark palette is an 'inverted dark', output of 'MiniBase16.mini_palette':
-- - Background '#E2E4D6' (LCh(uv) = 90-10-90)
-- - Foreground '#002DA0' (Lch(uv) = 15-70-250)
-- - Accent chroma 70
if vim.o.background == 'light' then
  palette = {
    base00 = '#e2e4d6',
    base01 = '#bec0b2',
    base02 = '#9b9d8f',
    base03 = '#797b6d',
    base04 = '#3d4eaf',
    base05 = '#002da0',
    base06 = '#0000ff',
    base07 = '#070500',
    base08 = '#662c00',
    base09 = '#ab6b1a',
    base0A = '#028d30',
    base0B = '#004d00',
    base0C = '#b555ae',
    base0D = '#005077',
    base0E = '#7d0075',
    base0F = '#008ab1',
  }
  use_cterm = {
    base00 = 254,
    base01 = 250,
    base02 = 247,
    base03 = 243,
    base04 = 61,
    base05 = 19,
    base06 = 21,
    base07 = 0,
    base08 = 52,
    base09 = 130,
    base0A = 29,
    base0B = 22,
    base0C = 133,
    base0D = 24,
    base0E = 90,
    base0F = 31,
  }
end

if palette then
  require('mini.base16').apply(palette, 'minischeme', use_cterm)
end