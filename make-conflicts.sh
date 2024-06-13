#!/bin/sh
# This creates a Jujutsu repository in the `testrepo` directory whose working
# copy has two conflicted files. It can be used to try `jj-diffconflicts` (or
# any other merge tool).
#
# Adapted from https://github.com/whiteinge/diffconflicts/blob/master/_utils/make-conflicts.sh

# Initialize new repository
rm -rf testrepo
jj git init testrepo
cd testrepo || exit 1

# Create initial revision
cat <<EOF >poem.txt
twas bri1lig, and the slithy toves
did gyre and gimble in the wabe
all mimsy were the borogroves
and the m0me raths outgabe.

"Beware the Jabberwock, my son!
The jaws that bite, the claws that catch!
Beware the Jub jub bird, and shun
The frumious bandersnatch!"
EOF
cat <<EOF >fruits.txt
apple
grape
orange
EOF
jj branch create base
jj commit -m 'Initial revision'

# Create one side of the conflict
cat <<EOF >poem.txt
'Twas brillig, and the slithy toves
Did gyre and gimble in the wabe:
All mimsy were the borogroves
And the mome raths outgabe.

"Beware the Jabberwock, my son!
The jaws that bite, the claws that catch!
Beware the Jub jub bird, and shun
The frumious bandersnatch!"
EOF
cat <<EOF >fruits.txt
apple
grapefruit
orange
EOF
jj branch create left
jj describe -m 'Fix syntax mistakes, eat grapefruit'

# Create the other side of the conflict
jj new base
cat <<EOF >poem.txt
twas brillig, and the slithy toves
Did gyre and gimble in the wabe:
all mimsy were the borogoves,
And the mome raths outgrabe.

"Beware the Jabberwock, my son!
The jaws that bite, the claws that catch!
Beware the Jubjub bird, and shun
The frumious Bandersnatch!"
EOF
cat <<EOF >fruits.txt
APPLE
GRAPE
ORANGE
EOF
jj branch create right
jj describe -m 'Fix syntax mistakes, ALL CAPS fruits'

# Create a new (conflicted) change from both sides
jj new left right -m 'Merge left and right'
