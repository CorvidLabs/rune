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

    # `ScreenRenderer::CSI` was widened to the full ECMA-48 grammar — parameter
    # bytes, then intermediates, then a final byte — after a real capture of one
    # agent contained 80 sequences it printed instead of obeying. The sanitizer
    # kept the narrower pattern, so the same sequences survived into
    # `clean_output`, `--grep` and `list`'s `last_line` while `--screen`
    # rendered them correctly. Two parsers in one module, one fixed and one not.
    it 'strips the CSI forms the renderer already understood' do
      expect(described_class.strip_ansi("\e[38:2::255:0:0mERROR\e[0m")).to eq('ERROR')
      expect(described_class.strip_ansi("\e[4:3municurl\e[0m")).to eq('unicurl')
      expect(described_class.strip_ansi("\e[2 q$ ready")).to eq('$ ready')
      expect(described_class.strip_ansi("\e[!pafter")).to eq('after')
    end

    # The widened parameter and intermediate classes must not start eating text.
    it 'still leaves colons, brackets and digits in ordinary text alone' do
      expect(described_class.strip_ansi('ratio a:b in [1;2] is 3:4')).to eq('ratio a:b in [1;2] is 3:4')
      expect(described_class.strip_ansi('12:34:56 elapsed')).to eq('12:34:56 elapsed')
    end
  end
end
