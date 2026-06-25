from rule_scrub_tags import scrub_text


def test_trailing_date_conversion_enabled():
    s = "Song Title - 19841119"
    scrub_text.convert_trailing_date_enabled = True
    out, rules = scrub_text(s, do_title_case=False)
    assert out == "Song Title (November 19, 1984)"
    assert "trailing_date_paren" in rules


def test_trailing_date_with_dashes():
    s = "Another Song - 1984-11-19"
    scrub_text.convert_trailing_date_enabled = True
    out, rules = scrub_text(s, do_title_case=False)
    assert out == "Another Song (November 19, 1984)"
    assert "trailing_date_paren" in rules


def test_trailing_date_disabled_by_default():
    s = "No Change - 19841119"
    scrub_text.convert_trailing_date_enabled = False
    out, rules = scrub_text(s, do_title_case=False)
    assert out == "No Change - 19841119"
    assert "trailing_date_paren" not in rules
