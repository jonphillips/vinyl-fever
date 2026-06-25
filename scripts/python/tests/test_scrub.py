import pytest

from rule_scrub_tags import (
    leading_disc_track_prefix,
    leading_track_prefix,
    strip_trailing_garbage,
)


def test_leading_disc_track_prefix_basic():
    assert leading_disc_track_prefix("101 Foo") == (1, 1, "Foo")
    assert leading_disc_track_prefix("214 - Bar") == (2, 14, "Bar")
    assert leading_disc_track_prefix("101Foo") == (None, None, None)
    assert leading_disc_track_prefix("2-1.") == (None, None, None)


def test_leading_track_prefix_basic():
    assert leading_track_prefix("06 Light of Day") == (6, "Light of Day")
    assert leading_track_prefix("6. Song") == (6, "Song")
    assert leading_track_prefix("2-1.") == (None, None)


def test_strip_trailing_garbage():
    out, rules = strip_trailing_garbage("Song - ")
    assert out == "Song"
    assert "drop_trailing_dash" in rules

    out2, rules2 = strip_trailing_garbage("Tune ,,,")
    assert out2 == "Tune"
    assert "drop_trailing_punct" in rules2
