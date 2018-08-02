# Twitter name finder

This spams Twitter to basically brute force for an *available* username with some parameters. Great for finding a name for your little startup or whatever.

It's only confirmed to work as of the date of the last commit. (Good luck.)

For the sake of Twitter, I won't explain how to use it, but the code is readable.

I generate names by representing strings as a number with a radix of the size of the alphabet I'm using. Like that, you can go from 'aaaa', 'aaab', ..., 'zzzz' just by incrementing a number and resume the brute force search (e.g., after a crash) in constant time.
