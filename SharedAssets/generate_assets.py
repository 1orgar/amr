import os
import subprocess
import json

BASE_DIR = "/Users/kirill/Documents/projects/amr"
SHARED_DIR = os.path.join(BASE_DIR, "SharedAssets")
COVERS_DIR = os.path.join(SHARED_DIR, "StationCovers")
ICONS_DIR = os.path.join(SHARED_DIR, "Icons")
IOS_ICONS_DIR = os.path.join(ICONS_DIR, "iOS")
MACOS_ICONS_DIR = os.path.join(ICONS_DIR, "macOS")
XC_ASSETS_DIR = os.path.join(SHARED_DIR, "Assets.xcassets")

os.makedirs(COVERS_DIR, exist_ok=True)
os.makedirs(IOS_ICONS_DIR, exist_ok=True)
os.makedirs(MACOS_ICONS_DIR, exist_ok=True)
os.makedirs(XC_ASSETS_DIR, exist_ok=True)

# -------------------------------------------------------------
# 1. Master SVGs
# -------------------------------------------------------------

APP_ICON_MASTER_SVG = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <defs>
    <linearGradient id="bgGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#0c0a18"/>
      <stop offset="35%" stop-color="#150f28"/>
      <stop offset="70%" stop-color="#1f1138"/>
      <stop offset="100%" stop-color="#2a0f40"/>
    </linearGradient>

    <linearGradient id="glassFill" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#ffffff" stop-opacity="0.10"/>
      <stop offset="100%" stop-color="#ffffff" stop-opacity="0.02"/>
    </linearGradient>

    <linearGradient id="glassBorder" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#ffffff" stop-opacity="0.55"/>
      <stop offset="25%" stop-color="#ff2d55" stop-opacity="0.45"/>
      <stop offset="70%" stop-color="#af52de" stop-opacity="0.40"/>
      <stop offset="100%" stop-color="#00f2fe" stop-opacity="0.30"/>
    </linearGradient>

    <linearGradient id="musicGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#fa233b"/>
      <stop offset="22%" stop-color="#ff2d55"/>
      <stop offset="50%" stop-color="#c837ab"/>
      <stop offset="75%" stop-color="#7928ca"/>
      <stop offset="100%" stop-color="#00d2ff"/>
    </linearGradient>

    <linearGradient id="signalGrad" x1="0%" y1="100%" x2="100%" y2="0%">
      <stop offset="0%" stop-color="#fa233b"/>
      <stop offset="45%" stop-color="#ff2d55"/>
      <stop offset="100%" stop-color="#00f2fe"/>
    </linearGradient>

    <filter id="noteShadow" x="-30%" y="-30%" width="160%" height="160%">
      <feDropShadow dx="0" dy="18" stdDeviation="22" flood-color="#fa233b" flood-opacity="0.55"/>
      <feDropShadow dx="0" dy="6" stdDeviation="12" flood-color="#000000" flood-opacity="0.6"/>
    </filter>

    <filter id="softGlow" x="-20%" y="-20%" width="140%" height="140%">
      <feGaussianBlur in="SourceGraphic" stdDeviation="12" result="blur"/>
      <feMerge>
        <feMergeNode in="blur"/>
        <feMergeNode in="SourceGraphic"/>
      </feMerge>
    </filter>

    <radialGradient id="redSpot" cx="50%" cy="50%" r="50%">
      <stop offset="0%" stop-color="#fa233b" stop-opacity="0.4"/>
      <stop offset="100%" stop-color="#fa233b" stop-opacity="0"/>
    </radialGradient>

    <radialGradient id="purpleSpot" cx="50%" cy="50%" r="50%">
      <stop offset="0%" stop-color="#7928ca" stop-opacity="0.45"/>
      <stop offset="100%" stop-color="#7928ca" stop-opacity="0"/>
    </radialGradient>
  </defs>

  <rect width="1024" height="1024" fill="url(#bgGrad)"/>
  <circle cx="300" cy="320" r="340" fill="url(#redSpot)"/>
  <circle cx="740" cy="460" r="360" fill="url(#purpleSpot)"/>

  <!-- Background Acoustic Waveform Bars -->
  <g opacity="0.16">
    <rect x="200" y="450" width="8" height="124" rx="4" fill="#ffffff"/>
    <rect x="230" y="400" width="8" height="224" rx="4" fill="#ffffff"/>
    <rect x="260" y="360" width="8" height="304" rx="4" fill="#ffffff"/>
    <rect x="290" y="420" width="8" height="184" rx="4" fill="#ffffff"/>
    <rect x="730" y="430" width="8" height="164" rx="4" fill="#ffffff"/>
    <rect x="760" y="370" width="8" height="284" rx="4" fill="#ffffff"/>
    <rect x="790" y="330" width="8" height="364" rx="4" fill="#ffffff"/>
    <rect x="820" y="410" width="8" height="204" rx="4" fill="#ffffff"/>
  </g>

  <!-- Central Frosted Glass Shield -->
  <rect x="144" y="144" width="736" height="736" rx="175" fill="url(#glassFill)" stroke="url(#glassBorder)" stroke-width="2.5"/>

  <!-- Specular Reflection -->
  <path d="M 170 190 C 340 160, 684 160, 854 190 C 864 230, 868 310, 848 390 C 660 310, 364 310, 174 390 Z" fill="#ffffff" opacity="0.05"/>

  <!-- Wireless Remote Broadcast Waves -->
  <g fill="none" stroke-linecap="round">
    <path d="M 650 330 A 230 230 0 0 1 750 430" stroke="url(#signalGrad)" stroke-width="13" opacity="0.95" filter="url(#softGlow)"/>
    <path d="M 685 295 A 280 280 0 0 1 805 415" stroke="url(#signalGrad)" stroke-width="10" opacity="0.75" filter="url(#softGlow)"/>
    <path d="M 720 260 A 330 330 0 0 1 860 400" stroke="url(#signalGrad)" stroke-width="7" opacity="0.5"/>
  </g>

  <!-- Sound Equalizer Matrix in Glass Body -->
  <g opacity="0.85" filter="url(#softGlow)">
    <rect x="295" y="485" width="11" height="115" rx="5.5" fill="url(#musicGrad)"/>
    <rect x="325" y="445" width="11" height="175" rx="5.5" fill="url(#musicGrad)"/>
    <rect x="355" y="525" width="11" height="85" rx="5.5" fill="url(#musicGrad)"/>
    
    <rect x="645" y="465" width="11" height="145" rx="5.5" fill="url(#musicGrad)"/>
    <rect x="675" y="425" width="11" height="205" rx="5.5" fill="url(#musicGrad)"/>
    <rect x="705" y="505" width="11" height="105" rx="5.5" fill="url(#musicGrad)"/>
  </g>

  <!-- Double Eighth Note Glyph -->
  <g filter="url(#noteShadow)">
    <ellipse cx="388" cy="670" rx="76" ry="56" transform="rotate(-22 388 670)" fill="url(#musicGrad)"/>
    <ellipse cx="638" cy="580" rx="76" ry="56" transform="rotate(-22 638 580)" fill="url(#musicGrad)"/>

    <rect x="442" y="325" width="28" height="345" rx="4" fill="url(#musicGrad)"/>
    <rect x="692" y="235" width="28" height="345" rx="4" fill="url(#musicGrad)"/>

    <polygon points="442,325 720,235 720,298 442,388" fill="url(#musicGrad)"/>
    <polygon points="442,410 720,320 720,358 442,448" fill="url(#musicGrad)" opacity="0.9"/>
  </g>

  <!-- Specular Highlights -->
  <g fill="#ffffff" opacity="0.3">
    <polygon points="444,327 718,237 718,247 444,337"/>
    <ellipse cx="374" cy="658" rx="38" ry="22" transform="rotate(-22 374 658)" fill="#ffffff" opacity="0.25"/>
    <ellipse cx="624" cy="568" rx="38" ry="22" transform="rotate(-22 624 568)" fill="#ffffff" opacity="0.25"/>
  </g>
</svg>"""

APP_ICON_MAC_SVG = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <defs>
    <filter id="macSquircleShadow" x="-20%" y="-20%" width="140%" height="150%">
      <feDropShadow dx="0" dy="28" stdDeviation="28" flood-color="#000000" flood-opacity="0.55"/>
      <feDropShadow dx="0" dy="8" stdDeviation="12" flood-color="#000000" flood-opacity="0.35"/>
    </filter>

    <linearGradient id="macBgGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#0c0a18"/>
      <stop offset="35%" stop-color="#150f28"/>
      <stop offset="70%" stop-color="#1f1138"/>
      <stop offset="100%" stop-color="#2a0f40"/>
    </linearGradient>

    <linearGradient id="macGlassFill" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#ffffff" stop-opacity="0.10"/>
      <stop offset="100%" stop-color="#ffffff" stop-opacity="0.02"/>
    </linearGradient>

    <linearGradient id="macGlassBorder" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#ffffff" stop-opacity="0.55"/>
      <stop offset="25%" stop-color="#ff2d55" stop-opacity="0.40"/>
      <stop offset="70%" stop-color="#af52de" stop-opacity="0.35"/>
      <stop offset="100%" stop-color="#00f2fe" stop-opacity="0.25"/>
    </linearGradient>

    <linearGradient id="macMusicGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#fa233b"/>
      <stop offset="22%" stop-color="#ff2d55"/>
      <stop offset="50%" stop-color="#c837ab"/>
      <stop offset="75%" stop-color="#7928ca"/>
      <stop offset="100%" stop-color="#00d2ff"/>
    </linearGradient>

    <linearGradient id="macSignalGrad" x1="0%" y1="100%" x2="100%" y2="0%">
      <stop offset="0%" stop-color="#fa233b"/>
      <stop offset="45%" stop-color="#ff2d55"/>
      <stop offset="100%" stop-color="#00f2fe"/>
    </linearGradient>

    <filter id="macNoteShadow" x="-30%" y="-30%" width="160%" height="160%">
      <feDropShadow dx="0" dy="14" stdDeviation="20" flood-color="#fa233b" flood-opacity="0.5"/>
      <feDropShadow dx="0" dy="5" stdDeviation="10" flood-color="#000000" flood-opacity="0.6"/>
    </filter>

    <filter id="macSoftGlow" x="-20%" y="-20%" width="140%" height="140%">
      <feGaussianBlur in="SourceGraphic" stdDeviation="12" result="blur"/>
      <feMerge>
        <feMergeNode in="blur"/>
        <feMergeNode in="SourceGraphic"/>
      </feMerge>
    </filter>

    <radialGradient id="macRedSpot" cx="50%" cy="50%" r="50%">
      <stop offset="0%" stop-color="#fa233b" stop-opacity="0.4"/>
      <stop offset="100%" stop-color="#fa233b" stop-opacity="0"/>
    </radialGradient>

    <radialGradient id="macPurpleSpot" cx="50%" cy="50%" r="50%">
      <stop offset="0%" stop-color="#7928ca" stop-opacity="0.45"/>
      <stop offset="100%" stop-color="#7928ca" stop-opacity="0"/>
    </radialGradient>

    <clipPath id="squircleClip">
      <rect x="100" y="100" width="824" height="824" rx="185"/>
    </clipPath>
  </defs>

  <!-- macOS App Squircle -->
  <rect x="100" y="100" width="824" height="824" rx="185" fill="url(#macBgGrad)" filter="url(#macSquircleShadow)"/>

  <!-- Inside Squircle -->
  <g clip-path="url(#squircleClip)">
    <circle cx="320" cy="320" r="300" fill="url(#macRedSpot)"/>
    <circle cx="720" cy="450" r="320" fill="url(#macPurpleSpot)"/>

    <g opacity="0.16">
      <rect x="210" y="440" width="8" height="144" rx="4" fill="#ffffff"/>
      <rect x="240" y="400" width="8" height="224" rx="4" fill="#ffffff"/>
      <rect x="270" y="360" width="8" height="304" rx="4" fill="#ffffff"/>
      <rect x="300" y="420" width="8" height="184" rx="4" fill="#ffffff"/>
      <rect x="720" y="430" width="8" height="164" rx="4" fill="#ffffff"/>
      <rect x="750" y="370" width="8" height="284" rx="4" fill="#ffffff"/>
      <rect x="780" y="330" width="8" height="364" rx="4" fill="#ffffff"/>
      <rect x="810" y="410" width="8" height="204" rx="4" fill="#ffffff"/>
    </g>

    <rect x="180" y="180" width="664" height="664" rx="150" fill="url(#macGlassFill)" stroke="url(#macGlassBorder)" stroke-width="2"/>

    <g fill="none" stroke-linecap="round">
      <path d="M 640 340 A 220 220 0 0 1 735 435" stroke="url(#macSignalGrad)" stroke-width="12" opacity="0.95" filter="url(#macSoftGlow)"/>
      <path d="M 672 308 A 265 265 0 0 1 785 420" stroke="url(#macSignalGrad)" stroke-width="9" opacity="0.75" filter="url(#macSoftGlow)"/>
      <path d="M 704 275 A 310 310 0 0 1 835 405" stroke="url(#macSignalGrad)" stroke-width="6.5" opacity="0.5"/>
    </g>

    <g opacity="0.85" filter="url(#macSoftGlow)">
      <rect x="310" y="480" width="11" height="110" rx="5.5" fill="url(#macMusicGrad)"/>
      <rect x="338" y="445" width="11" height="165" rx="5.5" fill="url(#macMusicGrad)"/>
      <rect x="366" y="520" width="11" height="85" rx="5.5" fill="url(#macMusicGrad)"/>
      
      <rect x="646" y="465" width="11" height="140" rx="5.5" fill="url(#macMusicGrad)"/>
      <rect x="674" y="430" width="11" height="195" rx="5.5" fill="url(#macMusicGrad)"/>
      <rect x="702" y="500" width="11" height="105" rx="5.5" fill="url(#macMusicGrad)"/>
    </g>

    <g filter="url(#macNoteShadow)">
      <ellipse cx="395" cy="660" rx="72" ry="54" transform="rotate(-22 395 660)" fill="url(#macMusicGrad)"/>
      <ellipse cx="630" cy="575" rx="72" ry="54" transform="rotate(-22 630 575)" fill="url(#macMusicGrad)"/>

      <rect x="445" y="340" width="26" height="320" rx="3.5" fill="url(#macMusicGrad)"/>
      <rect x="680" y="255" width="26" height="320" rx="3.5" fill="url(#macMusicGrad)"/>

      <polygon points="445,340 706,255 706,315 445,400" fill="url(#macMusicGrad)"/>
      <polygon points="445,420 706,335 706,370 445,455" fill="url(#macMusicGrad)" opacity="0.9"/>
    </g>

    <g fill="#ffffff" opacity="0.3">
      <polygon points="447,342 704,257 704,267 447,352"/>
      <ellipse cx="382" cy="648" rx="36" ry="22" transform="rotate(-22 382 648)" fill="#ffffff" opacity="0.25"/>
      <ellipse cx="617" cy="563" rx="36" ry="22" transform="rotate(-22 617 563)" fill="#ffffff" opacity="0.25"/>
    </g>

    <rect x="100" y="100" width="824" height="824" rx="185" fill="none" stroke="#ffffff" stroke-width="1.5" stroke-opacity="0.2"/>
  </g>
</svg>"""

# -------------------------------------------------------------
# 2. Curated Station Covers (12 Stations)
# -------------------------------------------------------------

STATION_SVGS = {
    "PersonalStation": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000" width="1000" height="1000">
  <defs>
    <linearGradient id="pBg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#2a001a"/>
      <stop offset="35%" stop-color="#fa233b"/>
      <stop offset="70%" stop-color="#ff007f"/>
      <stop offset="100%" stop-color="#7928ca"/>
    </linearGradient>
    <linearGradient id="waveGrad" x1="0%" y1="0%" x2="100%" y2="0%">
      <stop offset="0%" stop-color="#ffffff" stop-opacity="0.8"/>
      <stop offset="50%" stop-color="#ffc1cc" stop-opacity="0.9"/>
      <stop offset="100%" stop-color="#ffffff" stop-opacity="0.8"/>
    </linearGradient>
    <filter id="pGlow" x="-20%" y="-20%" width="140%" height="140%">
      <feGaussianBlur stdDeviation="16" result="blur"/>
      <feMerge><feMergeNode in="blur"/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>
  </defs>
  <rect width="1000" height="1000" fill="url(#pBg)"/>
  
  <!-- Soundwave Fingerprint Rings -->
  <g fill="none" stroke="url(#waveGrad)" stroke-linecap="round" opacity="0.85" filter="url(#pGlow)">
    <circle cx="500" cy="450" r="80" stroke-width="6"/>
    <circle cx="500" cy="450" r="140" stroke-width="8" stroke-dasharray="20 15 40 15"/>
    <circle cx="500" cy="450" r="200" stroke-width="10" stroke-dasharray="60 20 15 20 30 20"/>
    <circle cx="500" cy="450" r="260" stroke-width="8" stroke-dasharray="100 25 40 25"/>
    <circle cx="500" cy="450" r="320" stroke-width="6" stroke-dasharray="40 30 80 30"/>
  </g>

  <!-- Central Heartbeat / Wave Icon -->
  <g filter="url(#pGlow)">
    <path d="M 280 450 Q 380 450, 420 450 L 450 320 L 480 580 L 510 380 L 540 500 L 570 450 Q 620 450, 720 450" fill="none" stroke="#ffffff" stroke-width="16" stroke-linecap="round" stroke-linejoin="round"/>
  </g>

  <!-- Apple Music Header Badge -->
  <g transform="translate(500, 110)">
    <rect x="-130" y="-22" width="260" height="44" rx="22" fill="#000000" fill-opacity="0.35"/>
    <text x="0" y="7" fill="#ffffff" font-family="-apple-system, SF Pro Display, Helvetica Neue, sans-serif" font-size="20" font-weight="700" letter-spacing="4" text-anchor="middle">APPLE MUSIC</text>
  </g>

  <!-- Title Typography -->
  <text x="500" y="840" fill="#ffffff" font-family="-apple-system, SF Pro Display, Helvetica Neue, sans-serif" font-size="64" font-weight="900" letter-spacing="2" text-anchor="middle">МОЯ СТАНЦИЯ</text>
  <text x="500" y="890" fill="#ffc2d4" font-family="-apple-system, SF Pro Display, Helvetica Neue, sans-serif" font-size="26" font-weight="600" letter-spacing="6" text-anchor="middle">PERSONAL STATION</text>
</svg>""",

    "DiscoveryStation": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000" width="1000" height="1000">
  <defs>
    <linearGradient id="dBg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#0a0017"/>
      <stop offset="35%" stop-color="#3b0078"/>
      <stop offset="70%" stop-color="#7928ca"/>
      <stop offset="100%" stop-color="#ff007f"/>
    </linearGradient>
    <linearGradient id="starGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#00f2fe"/>
      <stop offset="50%" stop-color="#ffffff"/>
      <stop offset="100%" stop-color="#ff007f"/>
    </linearGradient>
    <filter id="dGlow" x="-30%" y="-30%" width="160%" height="160%">
      <feGaussianBlur stdDeviation="20" result="blur"/>
      <feMerge><feMergeNode in="blur"/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>
  </defs>
  <rect width="1000" height="1000" fill="url(#dBg)"/>

  <!-- Orbiting Cosmic Acoustic Rings -->
  <g fill="none" stroke="#00f2fe" opacity="0.5" stroke-linecap="round" filter="url(#dGlow)">
    <ellipse cx="500" cy="450" rx="300" ry="120" stroke-width="4" transform="rotate(-25 500 450)"/>
    <ellipse cx="500" cy="450" rx="340" ry="140" stroke-width="3" stroke-dasharray="15 30" transform="rotate(35 500 450)"/>
  </g>

  <!-- Radiant 8-Pointed Discovery Starburst -->
  <g filter="url(#dGlow)">
    <!-- Primary Flare Points -->
    <path d="M 500 200 L 530 420 L 750 450 L 530 480 L 500 700 L 470 480 L 250 450 L 470 420 Z" fill="url(#starGrad)"/>
    <!-- Diagonal Subtle Points -->
    <path d="M 500 310 L 518 432 L 640 450 L 518 468 L 500 590 L 482 468 L 360 450 L 482 432 Z" fill="#ffffff" opacity="0.8" transform="rotate(45 500 450)"/>
    <circle cx="500" cy="450" r="28" fill="#ffffff"/>
  </g>

  <!-- Star particles -->
  <circle cx="320" cy="280" r="6" fill="#00f2fe" opacity="0.8"/>
  <circle cx="680" cy="260" r="8" fill="#ffffff" opacity="0.9"/>
  <circle cx="280" cy="620" r="7" fill="#ff007f" opacity="0.7"/>
  <circle cx="720" cy="600" r="5" fill="#00f2fe" opacity="0.8"/>

  <!-- Apple Music Header Badge -->
  <g transform="translate(500, 110)">
    <rect x="-130" y="-22" width="260" height="44" rx="22" fill="#000000" fill-opacity="0.35"/>
    <text x="0" y="7" fill="#ffffff" font-family="-apple-system, SF Pro Display, Helvetica Neue, sans-serif" font-size="20" font-weight="700" letter-spacing="4" text-anchor="middle">APPLE MUSIC</text>
  </g>

  <!-- Typography -->
  <text x="500" y="840" fill="#ffffff" font-family="-apple-system, SF Pro Display, Helvetica Neue, sans-serif" font-size="60" font-weight="900" letter-spacing="2" text-anchor="middle">СТАНЦИЯ ОТКРЫТИЙ</text>
  <text x="500" y="890" fill="#00f2fe" font-family="-apple-system, SF Pro Display, Helvetica Neue, sans-serif" font-size="26" font-weight="600" letter-spacing="6" text-anchor="middle">DISCOVERY STATION</text>
</svg>""",

    "AppleMusic1Live": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000" width="1000" height="1000">
  <defs>
    <linearGradient id="am1Bg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#0d0d10"/>
      <stop offset="50%" stop-color="#181820"/>
      <stop offset="100%" stop-color="#242430"/>
    </linearGradient>
    <linearGradient id="numGrad" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" stop-color="#ffffff"/>
      <stop offset="100%" stop-color="#a0a0b0"/>
    </linearGradient>
    <filter id="liveGlow" x="-20%" y="-20%" width="140%" height="140%">
      <feDropShadow dx="0" dy="0" stdDeviation="12" flood-color="#ff2d55" flood-opacity="0.8"/>
    </filter>
  </defs>
  <rect width="1000" height="1000" fill="url(#am1Bg)"/>

  <!-- Studio Mesh Grid & Broadcast Rings -->
  <g fill="none" stroke="#ffffff" opacity="0.12" stroke-linecap="round">
    <circle cx="500" cy="450" r="160" stroke-width="2"/>
    <circle cx="500" cy="450" r="220" stroke-width="2" stroke-dasharray="8 8"/>
    <circle cx="500" cy="450" r="280" stroke-width="2"/>
    <circle cx="500" cy="450" r="340" stroke-width="2" stroke-dasharray="12 12"/>
  </g>

  <!-- Big Stylized Studio "1" Glyph -->
  <g>
    <!-- Background disc -->
    <circle cx="500" cy="450" r="130" fill="#000000" fill-opacity="0.5" stroke="#ffffff" stroke-opacity="0.2" stroke-width="3"/>
    <text x="500" y="525" fill="url(#numGrad)" font-family="-apple-system, SF Pro Display, Helvetica Neue, sans-serif" font-size="220" font-weight="900" text-anchor="middle">1</text>
  </g>

  <!-- LIVE Studio Badge -->
  <g transform="translate(500, 240)" filter="url(#liveGlow)">
    <rect x="-90" y="-24" width="180" height="48" rx="24" fill="#ff2d55"/>
    <circle cx="-50" cy="0" r="8" fill="#ffffff"/>
    <text x="14" y="8" fill="#ffffff" font-family="-apple-system, SF Pro Display, Helvetica Neue, sans-serif" font-size="24" font-weight="900" letter-spacing="3" text-anchor="middle">LIVE</text>
  </g>

  <!-- Header -->
  <g transform="translate(500, 110)">
    <text x="0" y="0" fill="#ffffff" font-family="-apple-system, SF Pro Display, Helvetica Neue, sans-serif" font-size="22" font-weight="700" letter-spacing="6" text-anchor="middle" opacity="0.8">GLOBAL BROADCAST</text>
  </g>

  <!-- Typography -->
  <text x="500" y="830" fill="#ffffff" font-family="-apple-system, SF Pro Display, Helvetica Neue, sans-serif" font-size="64" font-weight="900" letter-spacing="3" text-anchor="middle">APPLE MUSIC 1</text>
  <text x="500" y="880" fill="#a0a0b2" font-family="-apple-system, SF Pro Display, Helvetica Neue, sans-serif" font-size="24" font-weight="600" letter-spacing="5" text-anchor="middle">THE NEW MUSIC THAT MATTERS</text>
</svg>""",

    "AppleMusicHits": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000" width="1000" height="1000">
  <defs>
    <linearGradient id="hitsBg" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" stop-color="#19042b"/>
      <stop offset="40%" stop-color="#4d0e52"/>
      <stop offset="70%" stop-color="#fa709a"/>
      <stop offset="100%" stop-color="#fee140"/>
    </linearGradient>
    <linearGradient id="sunGrad" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" stop-color="#fee140"/>
      <stop offset="60%" stop-color="#fa709a"/>
      <stop offset="100%" stop-color="#7028e4"/>
    </linearGradient>
    <filter id="hitsGlow" x="-20%" y="-20%" width="140%" height="140%">
      <feGaussianBlur stdDeviation="14" result="blur"/>
      <feMerge><feMergeNode in="blur"/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>
  </defs>
  <rect width="1000" height="1000" fill="url(#hitsBg)"/>

  <!-- Retro Horizon Synthwave Grid -->
  <g stroke="#ffffff" opacity="0.3" stroke-width="2">
    <line x1="0" y1="580" x2="1000" y2="580"/>
    <line x1="0" y1="620" x2="1000" y2="620"/>
    <line x1="0" y1="670" x2="1000" y2="670"/>
    <line x1="0" y1="730" x2="1000" y2="730"/>
    <!-- Perspective rays -->
    <line x1="500" y1="580" x2="100" y2="760"/>
    <line x1="500" y1="580" x2="300" y2="760"/>
    <line x1="500" y1="580" x2="500" y2="760"/>
    <line x1="500" y1="580" x2="700" y2="760"/>
    <line x1="500" y1="580" x2="900" y2="760"/>
  </g>

  <!-- Segmented Retro Sunset Disc -->
  <g filter="url(#hitsGlow)">
    <mask id="sunMask">
      <circle cx="500" cy="420" r="180" fill="#ffffff"/>
      <rect x="300" y="420" width="400" height="8" fill="#000000"/>
      <rect x="300" y="445" width="400" height="12" fill="#000000"/>
      <rect x="300" y="475" width="400" height="16" fill="#000000"/>
      <rect x="300" y="510" width="400" height="20" fill="#000000"/>
      <rect x="300" y="550" width="400" height="24" fill="#000000"/>
    </mask>
    <circle cx="500" cy="420" r="180" fill="url(#sunGrad)" mask="url(#sunMask)"/>
  </g>

  <!-- Apple Music Header Badge -->
  <g transform="translate(500, 110)">
    <rect x="-130" y="-22" width="260" height="44" rx="22" fill="#000000" fill-opacity="0.35"/>
    <text x="0" y="7" fill="#ffffff" font-family="-apple-system, SF Pro Display, Helvetica Neue, sans-serif" font-size="20" font-weight="700" letter-spacing="4" text-anchor="middle">APPLE MUSIC</text>
  </g>

  <!-- Typography -->
  <text x="500" y="840" fill="#ffffff" font-family="-apple-system, SF Pro Display, Helvetica Neue, sans-serif" font-size="64" font-weight="900" letter-spacing="3" text-anchor="middle">HITS RADIO</text>
  <text x="500" y="890" fill="#fee140" font-family="-apple-system, SF Pro Display, Helvetica Neue, sans-serif" font-size="24" font-weight="700" letter-spacing="6" text-anchor="middle">80s · 90s · 2000s CLASSICS</text>
</svg>""",

    "AppleMusicCountry": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000" width="1000" height="1000">
  <defs>
    <linearGradient id="cBg" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" stop-color="#1f0a02"/>
      <stop offset="40%" stop-color="#5a2405"/>
      <stop offset="70%" stop-color="#f09819"/>
      <stop offset="100%" stop-color="#ffd200"/>
    </linearGradient>
    <filter id="cGlow" x="-20%" y="-20%" width="140%" height="140%">
      <feGaussianBlur stdDeviation="12" result="blur"/>
      <feMerge><feMergeNode in="blur"/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>
  </defs>
  <rect width="1000" height="1000" fill="url(#cBg)"/>

  <!-- Acoustic Sunburst & Rosette Pattern -->
  <g fill="none" stroke="#ffffff" opacity="0.3" stroke-width="3">
    <circle cx="500" cy="440" r="220"/>
    <circle cx="500" cy="440" r="170" stroke-dasharray="10 10"/>
    <circle cx="500" cy="440" r="120"/>
  </g>

  <!-- Acoustic Guitar & Sunrise Silhouette -->
  <g filter="url(#cGlow)">
    <circle cx="500" cy="440" r="85" fill="#2d1004" stroke="#ffd200" stroke-width="8"/>
    <!-- Guitar Strings Across Hole -->
    <line x1="470" y1="200" x2="470" y2="680" stroke="#ffd200" stroke-width="4" opacity="0.9"/>
    <line x1="485" y1="200" x2="485" y2="680" stroke="#ffd200" stroke-width="4" opacity="0.9"/>
    <line x1="500" y1="200" x2="500" y2="680" stroke="#ffd200" stroke-width="4" opacity="0.9"/>
    <line x1="515" y1="200" x2="515" y2="680" stroke="#ffd200" stroke-width="4" opacity="0.9"/>
    <line x1="530" y1="200" x2="530" y2="680" stroke="#ffd200" stroke-width="4" opacity="0.9"/>
  </g>

  <!-- Apple Music Header Badge -->
  <g transform="translate(500, 110)">
    <rect x="-130" y="-22" width="260" height="44" rx="22" fill="#000000" fill-opacity="0.35"/>
    <text x="0" y="7" fill="#ffffff" font-family="-apple-system, SF Pro Display, Helvetica Neue, sans-serif" font-size="20" font-weight="700" letter-spacing="4" text-anchor="middle">APPLE MUSIC</text>
  </g>

  <!-- Typography -->
  <text x="500" y="830" fill="#ffffff" font-family="-apple-system, SF Pro Display, Helvetica Neue, sans-serif" font-size="64" font-weight="900" letter-spacing="3" text-anchor="middle">COUNTRY</text>
  <text x="500" y="880" fill="#ffe28a" font-family="-apple-system, SF Pro Display, Helvetica Neue, sans-serif" font-size="24" font-weight="700" letter-spacing="5" text-anchor="middle">WHERE COUNTRY MUSIC LIVES</text>
</svg>""",

    "ChillLoFi": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000" width="1000" height="1000">
  <defs>
    <linearGradient id="chillBg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#061928"/>
      <stop offset="35%" stop-color="#00667f"/>
      <stop offset="70%" stop-color="#00b4db"/>
      <stop offset="100%" stop-color="#9b51e0"/>
    </linearGradient>
    <linearGradient id="sineGrad" x1="0%" y1="0%" x2="100%" y2="0%">
      <stop offset="0%" stop-color="#00f2fe"/>
      <stop offset="50%" stop-color="#ffffff"/>
      <stop offset="100%" stop-color="#b388ff"/>
    </linearGradient>
    <filter id="chillGlow" x="-20%" y="-20%" width="140%" height="140%">
      <feGaussianBlur stdDeviation="15" result="blur"/>
      <feMerge><feMergeNode in="blur"/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>
  </defs>
  <rect width="1000" height="1000" fill="url(#chillBg)"/>

  <!-- Ambient Mist Orbs -->
  <circle cx="300" cy="350" r="180" fill="#00f2fe" opacity="0.25" filter="url(#chillGlow)"/>
  <circle cx="700" cy="500" r="220" fill="#9b51e0" opacity="0.3" filter="url(#chillGlow)"/>

  <!-- Serene Undulating Wave Ribbons -->
  <g fill="none" stroke="url(#sineGrad)" stroke-linecap="round" filter="url(#chillGlow)">
    <path d="M 100 420 C 300 300, 400 540, 600 420 C 750 320, 850 480, 900 420" stroke-width="12" opacity="0.95"/>
    <path d="M 100 480 C 300 360, 400 600, 600 480 C 750 380, 850 540, 900 480" stroke-width="8" opacity="0.6"/>
    <path d="M 100 360 C 300 240, 400 480, 600 360 C 750 260, 850 420, 900 360" stroke-width="6" opacity="0.4"/>
  </g>

  <!-- Floating Minimal Lo-Fi Cassette Glyphs -->
  <g transform="translate(500, 450)" opacity="0.85">
    <circle cx="-50" cy="0" r="24" fill="none" stroke="#ffffff" stroke-width="4"/>
    <circle cx="50" cy="0" r="24" fill="none" stroke="#ffffff" stroke-width="4"/>
    <line x1="-50" y1="24" x2="50" y2="24" stroke="#ffffff" stroke-width="3"/>
  </g>

  <!-- Apple Music Header Badge -->
  <g transform="translate(500, 110)">
    <rect x="-130" y="-22" width="260" height="44" rx="22" fill="#000000" fill-opacity="0.35"/>
    <text x="0" y="7" fill="#ffffff" font-family="-apple-system, SF Pro Display, Helvetica Neue, sans-serif" font-size="20" font-weight="700" letter-spacing="4" text-anchor="middle">APPLE MUSIC</text>
  </g>

  <!-- Typography -->
  <text x="500" y="830" fill="#ffffff" font-family="-apple-system, SF Pro Display, Helvetica Neue, sans-serif" font-size="64" font-weight="900" letter-spacing="3" text-anchor="middle">CHILL &amp; LO-FI</text>
  <text x="500" y="880" fill="#bdefff" font-family="-apple-system, SF Pro Display, Helvetica Neue, sans-serif" font-size="24" font-weight="600" letter-spacing="6" text-anchor="middle">LAID-BACK SOUNDS &amp; BEATS</text>
</svg>""",

    "PopHits": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000" width="1000" height="1000">
  <defs>
    <linearGradient id="popBg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#33001f"/>
      <stop offset="35%" stop-color="#fa2d48"/>
      <stop offset="70%" stop-color="#ff6b8b"/>
      <stop offset="100%" stop-color="#ffd166"/>
    </linearGradient>
    <filter id="popGlow" x="-20%" y="-20%" width="140%" height="140%">
      <feGaussianBlur stdDeviation="14" result="blur"/>
      <feMerge><feMergeNode in="blur"/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>
  </defs>
  <rect width="1000" height="1000" fill="url(#popBg)"/>

  <!-- Explosive Pop Star-Burst Graphic -->
  <g filter="url(#popGlow)" fill="#ffffff">
    <path d="M 500 240 L 535 390 L 680 430 L 545 480 L 500 640 L 455 480 L 320 430 L 465 390 Z" opacity="0.95"/>
    <circle cx="500" cy="435" r="30" fill="#fa2d48"/>
  </g>

  <!-- Sparkling Pop Diamonds -->
  <polygon points="300,300 315,330 345,345 315,360 300,390 285,360 255,345 285,330" fill="#ffffff" opacity="0.8"/>
  <polygon points="720,290 730,310 750,320 730,330 720,350 710,330 690,320 710,310" fill="#ffd166" opacity="0.9"/>
  <polygon points="260,560 270,580 290,590 270,600 260,620 250,600 230,590 250,580" fill="#ffffff" opacity="0.7"/>
  <polygon points="740,540 750,560 770,570 750,580 740,600 730,580 710,570 730,560" fill="#ffffff" opacity="0.8"/>

  <!-- Apple Music Header Badge -->
  <g transform="translate(500, 110)">
    <rect x="-130" y="-22" width="260" height="44" rx="22" fill="#000000" fill-opacity="0.35"/>
    <text x="0" y="7" fill="#ffffff" font-family="-apple-system, SF Pro Display, Helvetica Neue, sans-serif" font-size="20" font-weight="700" letter-spacing="4" text-anchor="middle">APPLE MUSIC</text>
  </g>

  <!-- Typography -->
  <text x="500" y="830" fill="#ffffff" font-family="-apple-system, SF Pro Display, Helvetica Neue, sans-serif" font-size="64" font-weight="900" letter-spacing="3" text-anchor="middle">POP HITS</text>
  <text x="500" y="880" fill="#ffffff" font-family="-apple-system, SF Pro Display, Helvetica Neue, sans-serif" font-size="24" font-weight="700" letter-spacing="6" text-anchor="middle">THE BIGGEST ANTHEMS</text>
</svg>""",

    "RockClassics": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000" width="1000" height="1000">
  <defs>
    <linearGradient id="rockBg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#141416"/>
      <stop offset="40%" stop-color="#2a150c"/>
      <stop offset="70%" stop-color="#e65100"/>
      <stop offset="100%" stop-color="#ff9800"/>
    </linearGradient>
    <linearGradient id="fireGrad" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" stop-color="#ffeb3b"/>
      <stop offset="50%" stop-color="#ff5722"/>
      <stop offset="100%" stop-color="#b71c1c"/>
    </linearGradient>
    <filter id="rockGlow" x="-20%" y="-20%" width="140%" height="140%">
      <feGaussianBlur stdDeviation="16" result="blur"/>
      <feMerge><feMergeNode in="blur"/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>
  </defs>
  <rect width="1000" height="1000" fill="url(#rockBg)"/>

  <!-- Distortion Sound Waves -->
  <g fill="none" stroke="#ff9800" opacity="0.3" stroke-width="4">
    <circle cx="500" cy="440" r="230"/>
    <circle cx="500" cy="440" r="280" stroke-dasharray="14 14"/>
  </g>

  <!-- Heavy Guitar Pick Shield Emblem -->
  <g filter="url(#rockGlow)">
    <path d="M 330 290 Q 500 240, 670 290 Q 690 480, 500 630 Q 310 480, 330 290 Z" fill="#1b1c20" stroke="#ff9800" stroke-width="8"/>
    <!-- Lightning Bolt -->
    <polygon points="530,320 440,440 500,440 460,560 570,420 510,420" fill="url(#fireGrad)"/>
  </g>

  <!-- Apple Music Header Badge -->
  <g transform="translate(500, 110)">
    <rect x="-130" y="-22" width="260" height="44" rx="22" fill="#000000" fill-opacity="0.35"/>
    <text x="0" y="7" fill="#ffffff" font-family="-apple-system, SF Pro Display, Helvetica Neue, sans-serif" font-size="20" font-weight="700" letter-spacing="4" text-anchor="middle">APPLE MUSIC</text>
  </g>

  <!-- Typography -->
  <text x="500" y="830" fill="#ffffff" font-family="-apple-system, SF Pro Display, Helvetica Neue, sans-serif" font-size="64" font-weight="900" letter-spacing="3" text-anchor="middle">ROCK CLASSICS</text>
  <text x="500" y="880" fill="#ffb74d" font-family="-apple-system, SF Pro Display, Helvetica Neue, sans-serif" font-size="24" font-weight="700" letter-spacing="5" text-anchor="middle">GUITAR ANTHEMS &amp; LEGENDS</text>
</svg>""",

    "HipHopRap": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000" width="1000" height="1000">
  <defs>
    <linearGradient id="hipBg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#0c0116"/>
      <stop offset="40%" stop-color="#2a0845"/>
      <stop offset="70%" stop-color="#510087"/>
      <stop offset="100%" stop-color="#140026"/>
    </linearGradient>
    <linearGradient id="goldGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#fff099"/>
      <stop offset="30%" stop-color="#ffd700"/>
      <stop offset="70%" stop-color="#d4af37"/>
      <stop offset="100%" stop-color="#aa7c11"/>
    </linearGradient>
    <filter id="hipGlow" x="-20%" y="-20%" width="140%" height="140%">
      <feGaussianBlur stdDeviation="16" result="blur"/>
      <feMerge><feMergeNode in="blur"/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>
  </defs>
  <rect width="1000" height="1000" fill="url(#hipBg)"/>

  <!-- Heavy Sub-Bass Radiating Rings -->
  <g fill="none" stroke="url(#goldGrad)" opacity="0.4" stroke-linecap="round">
    <circle cx="500" cy="440" r="140" stroke-width="4"/>
    <circle cx="500" cy="440" r="200" stroke-width="6"/>
    <circle cx="500" cy="440" r="270" stroke-width="8" stroke-dasharray="15 25"/>
    <circle cx="500" cy="440" r="340" stroke-width="5"/>
  </g>

  <!-- 24K Polished Gold Crown Equalizer Bars -->
  <g filter="url(#hipGlow)" fill="url(#goldGrad)">
    <polygon points="350,510 380,380 430,450 500,320 570,450 620,380 650,510"/>
    <rect x="350" y="530" width="300" height="20" rx="10"/>
    <!-- Center Jewel -->
    <circle cx="500" cy="440" r="22" fill="#ffffff"/>
  </g>

  <!-- Apple Music Header Badge -->
  <g transform="translate(500, 110)">
    <rect x="-130" y="-22" width="260" height="44" rx="22" fill="#000000" fill-opacity="0.35"/>
    <text x="0" y="7" fill="#ffffff" font-family="-apple-system, SF Pro Display, Helvetica Neue, sans-serif" font-size="20" font-weight="700" letter-spacing="4" text-anchor="middle">APPLE MUSIC</text>
  </g>

  <!-- Typography -->
  <text x="500" y="830" fill="#ffffff" font-family="-apple-system, SF Pro Display, Helvetica Neue, sans-serif" font-size="64" font-weight="900" letter-spacing="3" text-anchor="middle">HIP-HOP &amp; RAP</text>
  <text x="500" y="880" fill="url(#goldGrad)" font-family="-apple-system, SF Pro Display, Helvetica Neue, sans-serif" font-size="24" font-weight="800" letter-spacing="6" text-anchor="middle">HEAVY BEATS &amp; RHYMES</text>
</svg>""",

    "DanceElectronic": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000" width="1000" height="1000">
  <defs>
    <linearGradient id="elecBg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#02120c"/>
      <stop offset="35%" stop-color="#004d40"/>
      <stop offset="70%" stop-color="#00c853"/>
      <stop offset="100%" stop-color="#00f5d4"/>
    </linearGradient>
    <linearGradient id="laserGrad" x1="0%" y1="0%" x2="100%" y2="0%">
      <stop offset="0%" stop-color="#00f5d4"/>
      <stop offset="50%" stop-color="#ffffff"/>
      <stop offset="100%" stop-color="#00e676"/>
    </linearGradient>
    <filter id="elecGlow" x="-20%" y="-20%" width="140%" height="140%">
      <feGaussianBlur stdDeviation="16" result="blur"/>
      <feMerge><feMergeNode in="blur"/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>
  </defs>
  <rect width="1000" height="1000" fill="url(#elecBg)"/>

  <!-- Cybernetic Synthesizer Grid -->
  <g stroke="#00f5d4" opacity="0.25" stroke-width="2">
    <line x1="200" y1="200" x2="800" y2="200"/>
    <line x1="200" y1="300" x2="800" y2="300"/>
    <line x1="200" y1="400" x2="800" y2="400"/>
    <line x1="200" y1="500" x2="800" y2="500"/>
    <line x1="200" y1="600" x2="800" y2="600"/>
    <line x1="200" y1="700" x2="800" y2="700"/>
    
    <line x1="200" y1="200" x2="200" y2="700"/>
    <line x1="320" y1="200" x2="320" y2="700"/>
    <line x1="440" y1="200" x2="440" y2="700"/>
    <line x1="560" y1="200" x2="560" y2="700"/>
    <line x1="680" y1="200" x2="680" y2="700"/>
    <line x1="800" y1="200" x2="800" y2="700"/>
  </g>

  <!-- Pulsating BPM Waveform -->
  <g filter="url(#elecGlow)" fill="none" stroke="url(#laserGrad)" stroke-width="12" stroke-linecap="round" stroke-linejoin="round">
    <path d="M 160 450 L 320 450 L 360 300 L 410 580 L 460 380 L 510 520 L 560 340 L 610 560 L 650 450 L 840 450"/>
  </g>

  <!-- Apple Music Header Badge -->
  <g transform="translate(500, 110)">
    <rect x="-130" y="-22" width="260" height="44" rx="22" fill="#000000" fill-opacity="0.35"/>
    <text x="0" y="7" fill="#ffffff" font-family="-apple-system, SF Pro Display, Helvetica Neue, sans-serif" font-size="20" font-weight="700" letter-spacing="4" text-anchor="middle">APPLE MUSIC</text>
  </g>

  <!-- Typography -->
  <text x="500" y="830" fill="#ffffff" font-family="-apple-system, SF Pro Display, Helvetica Neue, sans-serif" font-size="62" font-weight="900" letter-spacing="2" text-anchor="middle">DANCE &amp; ELECTRONIC</text>
  <text x="500" y="880" fill="#00f5d4" font-family="-apple-system, SF Pro Display, Helvetica Neue, sans-serif" font-size="24" font-weight="700" letter-spacing="6" text-anchor="middle">CLUB &amp; FESTIVAL BANGERS</text>
</svg>""",

    "DeepHouse": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000" width="1000" height="1000">
  <defs>
    <linearGradient id="dhBg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#140018"/>
      <stop offset="35%" stop-color="#4a0033"/>
      <stop offset="70%" stop-color="#880e4f"/>
      <stop offset="100%" stop-color="#d81b60"/>
    </linearGradient>
    <linearGradient id="magentaGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#ff4081"/>
      <stop offset="50%" stop-color="#ffffff"/>
      <stop offset="100%" stop-color="#880e4f"/>
    </linearGradient>
    <filter id="dhGlow" x="-20%" y="-20%" width="140%" height="140%">
      <feGaussianBlur stdDeviation="16" result="blur"/>
      <feMerge><feMergeNode in="blur"/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>
  </defs>
  <rect width="1000" height="1000" fill="url(#dhBg)"/>

  <!-- Hypnotic Deep Groove Rings -->
  <g fill="none" stroke="url(#magentaGrad)" stroke-linecap="round" opacity="0.75" filter="url(#dhGlow)">
    <circle cx="500" cy="440" r="70" stroke-width="5"/>
    <circle cx="500" cy="440" r="130" stroke-width="7" stroke-dasharray="30 20"/>
    <circle cx="500" cy="440" r="190" stroke-width="9" stroke-dasharray="60 30 15 30"/>
    <circle cx="500" cy="440" r="250" stroke-width="7" stroke-dasharray="100 40 40 40"/>
    <circle cx="500" cy="440" r="310" stroke-width="5"/>
  </g>

  <!-- Center Vinyl Core -->
  <circle cx="500" cy="440" r="35" fill="#140018" stroke="#ff4081" stroke-width="6"/>

  <!-- Apple Music Header Badge -->
  <g transform="translate(500, 110)">
    <rect x="-130" y="-22" width="260" height="44" rx="22" fill="#000000" fill-opacity="0.35"/>
    <text x="0" y="7" fill="#ffffff" font-family="-apple-system, SF Pro Display, Helvetica Neue, sans-serif" font-size="20" font-weight="700" letter-spacing="4" text-anchor="middle">APPLE MUSIC</text>
  </g>

  <!-- Typography -->
  <text x="500" y="830" fill="#ffffff" font-family="-apple-system, SF Pro Display, Helvetica Neue, sans-serif" font-size="64" font-weight="900" letter-spacing="3" text-anchor="middle">DEEP HOUSE</text>
  <text x="500" y="880" fill="#ff80ab" font-family="-apple-system, SF Pro Display, Helvetica Neue, sans-serif" font-size="24" font-weight="700" letter-spacing="6" text-anchor="middle">MELODIC &amp; HYPNOTIC RHYTHMS</text>
</svg>""",

    "JazzBlues": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000" width="1000" height="1000">
  <defs>
    <linearGradient id="jazzBg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#090d13"/>
      <stop offset="40%" stop-color="#16202c"/>
      <stop offset="75%" stop-color="#2d3e52"/>
      <stop offset="100%" stop-color="#1b2430"/>
    </linearGradient>
    <linearGradient id="brassGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#fdf4d8"/>
      <stop offset="35%" stop-color="#d4af37"/>
      <stop offset="70%" stop-color="#aa7c11"/>
      <stop offset="100%" stop-color="#f3e5ab"/>
    </linearGradient>
    <filter id="jazzGlow" x="-20%" y="-20%" width="140%" height="140%">
      <feGaussianBlur stdDeviation="14" result="blur"/>
      <feMerge><feMergeNode in="blur"/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>
  </defs>
  <rect width="1000" height="1000" fill="url(#jazzBg)"/>

  <!-- Elegant Acoustic Brass Wave Resonance -->
  <g fill="none" stroke="url(#brassGrad)" opacity="0.3" stroke-width="2">
    <circle cx="500" cy="440" r="230"/>
    <circle cx="500" cy="440" r="180"/>
    <circle cx="500" cy="440" r="130"/>
  </g>

  <!-- Brass Saxophone / Trumpet Acoustic Bell Curve -->
  <g filter="url(#jazzGlow)" fill="none" stroke="url(#brassGrad)" stroke-linecap="round">
    <!-- Outer Horn Flare -->
    <path d="M 360 560 C 380 400, 440 320, 620 280 C 650 274, 680 340, 640 370 C 510 420, 480 480, 480 580" stroke-width="12"/>
    <!-- Inner Horn Flare -->
    <path d="M 400 560 C 420 440, 460 370, 590 340" stroke-width="6" opacity="0.7"/>
    <!-- Musical Key Pearls -->
    <circle cx="480" cy="480" r="10" fill="url(#brassGrad)"/>
    <circle cx="475" cy="515" r="10" fill="url(#brassGrad)"/>
    <circle cx="470" cy="550" r="10" fill="url(#brassGrad)"/>
  </g>

  <!-- Apple Music Header Badge -->
  <g transform="translate(500, 110)">
    <rect x="-130" y="-22" width="260" height="44" rx="22" fill="#000000" fill-opacity="0.35"/>
    <text x="0" y="7" fill="#ffffff" font-family="-apple-system, SF Pro Display, Helvetica Neue, sans-serif" font-size="20" font-weight="700" letter-spacing="4" text-anchor="middle">APPLE MUSIC</text>
  </g>

  <!-- Typography -->
  <text x="500" y="830" fill="#ffffff" font-family="-apple-system, SF Pro Display, Helvetica Neue, sans-serif" font-size="64" font-weight="900" letter-spacing="3" text-anchor="middle">JAZZ &amp; BLUES</text>
  <text x="500" y="880" fill="url(#brassGrad)" font-family="-apple-system, SF Pro Display, Helvetica Neue, sans-serif" font-size="24" font-weight="700" letter-spacing="6" text-anchor="middle">TIMELESS STANDARDS &amp; SOUL</text>
</svg>"""
}

# Write SVGs to disk
print("Writing AppIcon SVGs...")
with open(os.path.join(SHARED_DIR, "AppIconMaster.svg"), "w") as f:
    f.write(APP_ICON_MASTER_SVG)

with open(os.path.join(SHARED_DIR, "AppIconMac.svg"), "w") as f:
    f.write(APP_ICON_MAC_SVG)

print("Writing Station Cover SVGs...")
for name, svg in STATION_SVGS.items():
    svg_path = os.path.join(COVERS_DIR, f"{name}.svg")
    with open(svg_path, "w") as f:
        f.write(svg)
    print(f"  -> {svg_path}")

print("All SVGs created successfully.")
