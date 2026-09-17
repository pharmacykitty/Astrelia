# Third-party notices

Astrelia's code is licensed under the GNU General Public License v3.0 (see `LICENSE`). The data it ships with comes from other people and keeps its own terms. The app shows the same credits under About → Sources.

## Stars

**HYG database v4.1** by David Nash (astronexus), CC BY-SA 4.0.
https://github.com/astronexus/HYG-Database
`App/Resources/stars.bin` is built from it by `Tools/build_star_catalog.py`. That file is a derivative of HYG and is shared under CC BY-SA 4.0, not the GPL.

## Constellation lines

`App/Resources/constellation_lines.json` comes from **d3-celestial** by Olaf Frohn (https://github.com/ofrohn/d3-celestial), under this license:

```
Copyright (c) 2015, Olaf Frohn
All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

## Nebulae

The 27 files in `App/Resources/Nebulae/` are particle sets derived offline from visible-light photographs. The photographs themselves are not in this repo, only the points.

- **ESA/Hubble & NASA** (CC BY 4.0, https://esahubble.org/copyright): Orion (heic0601a), Eagle (heic1501a), Lagoon (heic1808a), Tarantula (heic1402a), Crab (heic0515a), Veil (heic1520a), Ring (heic1310a), Helix (heic0307a), North America (heic0510a), Omega/M17 (heic0305a), Little Dumbbell/M76 (heic2408a), Southern Ring (opo9839a), Butterfly/NGC 6302 (heic0910h), Eskimo (heic9910a). Credit: ESA/Hubble & NASA and the Hubble Heritage Team (STScI/AURA).
- **ESO** (CC BY 4.0, https://www.eso.org/public/outreach/copyright): Trifid (eso0930a), Carina (eso0905a), Lobster/NGC 6357 (eso1207a), Horsehead (eso0202a), Dumbbell/M27 (opo0306c), Saturn Nebula (eso1731a), Vela supernova remnant (eso2214a). Credit: ESO.
- **NOIRLab** (CC BY 4.0, https://noirlab.edu/public/copyright): Pacman/NGC 281 (WIYN, T. A. Rector/UAA), Rosette/NGC 2237 (CTIO DECam, noirlab2424a), California/NGC 1499 (KPNO, Adam Block), Jellyfish/IC 443 (KPNO, T. Bash & J. Fox). Credit: KPNO/CTIO/NOIRLab/NSF/AURA.
- **NASA** (public domain, https://images.nasa.gov): Cone Nebula (NASA, STScI/HST), Bubble Nebula (NASA/GSFC).

## Exoplanets

`App/Resources/exoplanets.csv` is a snapshot of the Planetary Systems table. This research has made use of the NASA Exoplanet Archive, which is operated by the California Institute of Technology, under contract with the National Aeronautics and Space Administration under the Exoplanet Exploration Program.
https://exoplanetarchive.ipac.caltech.edu

## Everything else

- Planet and moon physical data: NASA/JPL planetary fact sheets (public domain).
- Meteor showers: the International Meteor Organization's working list.
- Habitable zones: Kopparapu et al. (2013).
- Star temperatures from B−V: Ballesteros (2012).
- The Sgr A* lensing is an original real-time approximation, inspired by NASA Goddard's "Beyond the Brink" visualization (J. Schnittman). No NASA media is included.
- The astronomy math lives in [AstroPackages](https://github.com/pharmacykitty/AstroPackages), which has its own `NOTICE.md` (Meeus, SwiftAA and friends).
