Ninety-two German pilot portraits, supplied by Patrick on 10 September
2026, replacing the twenty-five of the day before. The earlier set turned
out to be contained in this one, so nothing was lost by replacing the
folder outright.

Converted by dev/make_lw_portraits.py to the format the Room already uses
for the RAF set: 280 x 420 JPEG, about thirty kilobytes each. They arrive
at 1152 x 1728, which is the same 2:3 shape, so nothing has to be
cropped; the conversion crops to the exact ratio anyway rather than
scaling to fit, because squashing a face is worse than losing a few
pixels at an edge.

Patrick said there might be duplicates and there were: ninety-seven files
came in and five of them were repeats. None were byte-identical, so a
checksum found nothing. They are the same photograph saved more than
once, and they were caught by comparing what each picture looks like
rather than what it contains: one man in a flying helmet photographed
twice, and one photographed five times. The groups that were collapsed
are in portraits-dropped.png beside this folder, so the judgement can be
looked at rather than taken on trust.

portraits.json beside this folder lists them, exactly as the RAF one
does. Get-Portraits reads whichever of the two the current side points
at, so nothing here needs naming differently.
