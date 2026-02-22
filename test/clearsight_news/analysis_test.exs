defmodule ClearsightNews.AnalysisTest do
  use ExUnit.Case, async: true

  alias ClearsightNews.Analysis
  alias ClearsightNews.Analysis.{SentimentResult, Emotions, Rhetoric, Certainty}

  # ---------------------------------------------------------------------------
  # compute_sentiment_score/1
  # ---------------------------------------------------------------------------

  describe "compute_sentiment_score/1" do
    test "returns 0.0 for a fully neutral result" do
      result = %SentimentResult{
        tone: "neutral",
        emotions: %Emotions{},
        rhetoric: %Rhetoric{},
        loaded_language: 0.0,
        certainty: %Certainty{}
      }

      assert Analysis.compute_sentiment_score(result) == 0.0
    end

    test "positive tone with high joy/trust pushes score above threshold" do
      result = %SentimentResult{
        tone: "positive",
        emotions: %Emotions{joy: 0.8, trust: 0.7},
        rhetoric: %Rhetoric{analytical: 0.5, supportive: 0.5},
        loaded_language: 0.1,
        certainty: %Certainty{certainty: 0.8, speculation: 0.1}
      }

      score = Analysis.compute_sentiment_score(result)
      assert score > 0.1
    end

    test "negative tone with high anger/fear/sadness pushes score below threshold" do
      result = %SentimentResult{
        tone: "negative",
        emotions: %Emotions{anger: 0.8, fear: 0.7, sadness: 0.6},
        rhetoric: %Rhetoric{alarmist: 0.8, dismissive: 0.5},
        loaded_language: 0.9,
        certainty: %Certainty{certainty: 0.1, speculation: 0.8}
      }

      score = Analysis.compute_sentiment_score(result)
      assert score < -0.1
    end

    test "score is clamped to [-1.0, 1.0]" do
      extreme_positive = %SentimentResult{
        tone: "positive",
        emotions: %Emotions{joy: 1.0, trust: 1.0},
        rhetoric: %Rhetoric{supportive: 1.0, analytical: 1.0},
        loaded_language: 0.0,
        certainty: %Certainty{certainty: 1.0, speculation: 0.0}
      }

      extreme_negative = %SentimentResult{
        tone: "negative",
        emotions: %Emotions{anger: 1.0, fear: 1.0, sadness: 1.0, disgust: 1.0},
        rhetoric: %Rhetoric{alarmist: 1.0, dismissive: 1.0, sarcastic: 1.0},
        loaded_language: 1.0,
        certainty: %Certainty{certainty: 0.0, speculation: 1.0}
      }

      assert Analysis.compute_sentiment_score(extreme_positive) <= 1.0
      assert Analysis.compute_sentiment_score(extreme_negative) >= -1.0
    end

    test "handles nil embedded structs gracefully" do
      result = %SentimentResult{tone: "neutral", emotions: nil, rhetoric: nil, certainty: nil}
      # Should not raise
      score = Analysis.compute_sentiment_score(result)
      assert is_float(score)
    end
  end

  # ---------------------------------------------------------------------------
  # classify/1 and label/1
  # ---------------------------------------------------------------------------

  describe "classify/1" do
    test "score above 0.1 is :positive" do
      assert Analysis.classify(0.5) == :positive
      assert Analysis.classify(0.11) == :positive
    end

    test "score below -0.1 is :negative" do
      assert Analysis.classify(-0.5) == :negative
      assert Analysis.classify(-0.11) == :negative
    end

    test "score within threshold is :neutral" do
      assert Analysis.classify(0.0) == :neutral
      assert Analysis.classify(0.1) == :neutral
      assert Analysis.classify(-0.1) == :neutral
    end
  end

  describe "label/1" do
    test "returns capitalised string matching CSS class names" do
      assert Analysis.label(0.5) == "Positive"
      assert Analysis.label(-0.5) == "Negative"
      assert Analysis.label(0.0) == "Neutral"
    end
  end
end
