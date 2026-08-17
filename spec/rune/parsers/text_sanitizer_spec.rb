# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Rune::Parsers::TextSanitizer do
  describe '.strip_ansi' do
    it 'strips ANSI color codes' do
      colored_text = "\e[31mRed Text\e[0m and \e[32mGreen Text\e[0m"
      expect(described_class.strip_ansi(colored_text)).to eq('Red Text and Green Text')
    end

    it 'normalizes carriage returns and newlines' do
      text_with_cr = "Line 1\r\nLine 2\rLine 3"
      expect(described_class.strip_ansi(text_with_cr)).to eq("Line 1\nLine 2\nLine 3")
    end

    it 'handles nil inputs safely' do
      expect(described_class.strip_ansi(nil)).to eq('')
    end

    # Found by driving Claude Code through `rune session`: every read's
    # `clean_output` opened with a literal `\e7\e8`. Present uncapped as well as
    # capped, so the stripper rather than the truncation — and `ScreenRenderer`
    # already acted on `[DEM78c]`, so the two parsers in this module disagreed
    # about what an escape is.
    {
      "\e7saved\e8" => 'saved',                       # DECSC / DECRC
      "\eDindex" => 'index',                          # IND
      "\eEnextline" => 'nextline',                    # NEL
      "\eMreverse" => 'reverse',                      # RI
      "\ecreset" => 'reset',                          # RIS
      "\eHtabstop" => 'tabstop',                      # HTS
      "\e#8align" => 'align',                         # DECALN
      "\e%Gutf8" => 'utf8'                            # select UTF-8
    }.each do |raw, expected|
      it "strips #{raw.inspect}, which a renderer already treats as a control" do
        expect(described_class.strip_ansi(raw)).to eq(expected)
      end
    end

    # The charset branch was `[()][AB0K]`, so `\e(1` and `\e)0` survived and
    # dropped their final byte into the text as a stray letter.
    {
      "\e(0lqk\e(B" => 'lqk',
      "\e)0x\e)Bz" => 'xz',
      "\e*1a\e+Ab" => 'ab'
    }.each do |raw, expected|
      it "strips the charset designation #{raw.inspect} whichever slot it targets" do
        expect(described_class.strip_ansi(raw)).to eq(expected)
      end
    end

    # The escapes must not eat ordinary text that merely follows one.
    it 'leaves the text after an escape intact, including letters the escape could have matched' do
      expect(described_class.strip_ansi("\e7Done. Exit code 8, see D and M\e8")).to eq('Done. Exit code 8, see D and M')
    end

    it 'leaves text containing no escapes untouched' do
      expect(described_class.strip_ansi('plain 7 8 D E M c text')).to eq('plain 7 8 D E M c text')
    end
  end
end
