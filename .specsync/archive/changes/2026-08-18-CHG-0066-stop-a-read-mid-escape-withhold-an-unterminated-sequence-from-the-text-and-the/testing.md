---
change: CHG-0066-stop-a-read-mid-escape-withhold-an-unterminated-sequence-from-the-text-and-the
artifact: testing
---

# Testing

Verified on the reported reproduction, all three surfaces:

    before   read #1 clean_output "READY\n\e[3"  cursor 10
             read #2 clean_output "1mRED\n"      screen "READY\nRED"   list "1mRED"
    after    read #1 clean_output "READY\n"      cursor 7
             read #2 clean_output "RED\n"        screen "READY\nRED"   list "RED"

Each test falsified against deliberately unfixed code:

    mutation                              failures
    read-boundary withholding reverted    2 of 3
    list tail reassembly reverted         1 of 3

566 examples, 0 failures; rubocop clean across 72 files.
