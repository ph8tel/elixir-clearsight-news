defmodule ClearsightNews.AnalysisTest do
  use ExUnit.Case, async: true

  alias ClearsightNews.Analysis
  alias ClearsightNews.Analysis.{
    SentimentResult,
    RhetoricResult,
    ComparisonResult,
    Emotions,
    Rhetoric,
    Certainty
  }

  # ---------------------------------------------------------------------------
  # Shared fixtures and helpers
  # ---------------------------------------------------------------------------

  # Valid Groq tool-call argument payloads that satisfy each schema's validations.

  @sentiment_args %{
    "tone" => "positive",
    "loaded_language" => 0.2,
    "emotions" => %{
      "joy" => 0.8,
      "trust" => 0.6,
      "fear" => 0.0,
      "anger" => 0.0,
      "sadness" => 0.0,
      "anticipation" => 0.5,
      "disgust" => 0.0,
      "surprise" => 0.2
    },
    "rhetoric" => %{
      "analytical" => 0.7,
      "supportive" => 0.8,
      "persuasive" => 0.3,
      "alarmist" => 0.0,
      "dismissive" => 0.0,
      "sarcastic" => 0.0
    },
    "certainty" => %{"certainty" => 0.8, "speculation" => 0.1}
  }

  @rhetoric_args %{
    "overall_tone" => "measured",
    "sentiment_label" => "neutral",
    "rhetorical_devices" => [
      %{"device" => "appeal to authority", "example" => "experts say..."}
    ],
    "bias_indicators" => ["selective sourcing"]
  }

  @comparison_args %{
    "framing_differences" => "Article 1 focuses on economic impact",
    "tone_comparison" => "Article 1 is alarmist, Article 2 is measured",
    "source_selection" => "Different expert sources cited",
    "key_differences" => "Article 1 omits historical context",
    "bias_assessment" => "Article 2 appears more balanced"
  }

  # Wraps args in the Groq /tools response envelope that Instructor parses.
  defp stub_groq_ok(args_map) do
    Req.Test.stub(:groq_api, fn conn ->
      Req.Test.json(conn, %{
        "choices" => [
          %{
            "message" => %{
              "tool_calls" => [
                %{"function" => %{"arguments" => Jason.encode!(args_map)}}
              ]
            }
          }
        ]
      })
    end)
  end

  defp stub_groq_error(status) do
    Req.Test.stub(:groq_api, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(status, Jason.encode!(%{"message" => "error #{status}"}))
    end)
  end

  # ---------------------------------------------------------------------------
  # analyse_sentiment/1
  # ---------------------------------------------------------------------------

  describe "analyse_sentiment/1" do
    setup do
      stub_groq_ok(@sentiment_args)
      :ok
    end

    test "returns {:ok, %SentimentResult{}} with correct tone" do
      assert {:ok, %SentimentResult{tone: "positive"}} = Analysis.analyse_sentiment("Some news text")
    end

    test "populates embedded emotion scores" do
      {:ok, result} = Analysis.analyse_sentiment("text")
      assert result.emotions.joy == 0.8
      assert result.emotions.trust == 0.6
      assert result.emotions.fear == 0.0
    end

    test "populates embedded rhetoric scores" do
      {:ok, result} = Analysis.analyse_sentiment("text")
      assert result.rhetoric.analytical == 0.7
      assert result.rhetoric.supportive == 0.8
    end

    test "populates certainty and loaded_language fields" do
      {:ok, result} = Analysis.analyse_sentiment("text")
      assert result.certainty.certainty == 0.8
      assert result.certainty.speculation == 0.1
      assert result.loaded_language == 0.2
    end

    test "accepts text longer than 4000 chars without error" do
      long_text = String.duplicate("word ", 1000)
      assert {:ok, %SentimentResult{}} = Analysis.analyse_sentiment(long_text)
    end

    test "returns {:error, reason} on non-200 API response" do
      stub_groq_error(401)
      assert {:error, reason} = Analysis.analyse_sentiment("text")
      assert reason =~ "401"
    end

    test "returns {:error, reason} on server error" do
      stub_groq_error(500)
      assert {:error, _reason} = Analysis.analyse_sentiment("text")
    end
  end

  # ---------------------------------------------------------------------------
  # analyse_rhetoric/1
  # ---------------------------------------------------------------------------

  describe "analyse_rhetoric/1" do
    setup do
      stub_groq_ok(@rhetoric_args)
      :ok
    end

    test "returns {:ok, %RhetoricResult{}} on success" do
      assert {:ok, %RhetoricResult{}} = Analysis.analyse_rhetoric("Some article text")
    end

    test "populates overall_tone and sentiment_label" do
      {:ok, result} = Analysis.analyse_rhetoric("text")
      assert result.overall_tone == "measured"
      assert result.sentiment_label == "neutral"
    end

    test "populates rhetorical_devices list" do
      {:ok, result} = Analysis.analyse_rhetoric("text")
      assert [%{"device" => "appeal to authority", "example" => "experts say..."}] =
               result.rhetorical_devices
    end

    test "populates bias_indicators list" do
      {:ok, result} = Analysis.analyse_rhetoric("text")
      assert result.bias_indicators == ["selective sourcing"]
    end

    test "accepts empty rhetorical_devices and bias_indicators" do
      stub_groq_ok(%{@rhetoric_args | "rhetorical_devices" => [], "bias_indicators" => []})
      {:ok, result} = Analysis.analyse_rhetoric("text")
      assert result.rhetorical_devices == []
      assert result.bias_indicators == []
    end

    test "returns {:error, reason} on API error" do
      stub_groq_error(429)
      assert {:error, _reason} = Analysis.analyse_rhetoric("text")
    end
  end

  # ---------------------------------------------------------------------------
  # analyse_comparison/2
  # ---------------------------------------------------------------------------

  describe "analyse_comparison/2" do
    setup do
      stub_groq_ok(@comparison_args)
      :ok
    end

    test "returns {:ok, %ComparisonResult{}} on success" do
      assert {:ok, %ComparisonResult{}} = Analysis.analyse_comparison("Article 1", "Article 2")
    end

    test "populates all required string fields" do
      {:ok, result} = Analysis.analyse_comparison("text1", "text2")
      assert is_binary(result.framing_differences)
      assert is_binary(result.tone_comparison)
      assert is_binary(result.source_selection)
      assert is_binary(result.key_differences)
      assert is_binary(result.bias_assessment)
    end

    test "framing_differences contains expected content" do
      {:ok, result} = Analysis.analyse_comparison("t1", "t2")
      assert result.framing_differences =~ "economic impact"
    end

    test "returns {:error, reason} on API error" do
      stub_groq_error(503)
      assert {:error, _reason} = Analysis.analyse_comparison("t1", "t2")
    end
  end

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

      assert Analysis.compute_sentiment_score(result) > 0.1
    end

    test "negative tone with high anger/fear/sadness pushes score below threshold" do
      result = %SentimentResult{
        tone: "negative",
        emotions: %Emotions{anger: 0.8, fear: 0.7, sadness: 0.6},
        rhetoric: %Rhetoric{alarmist: 0.8, dismissive: 0.5},
        loaded_language: 0.9,
        certainty: %Certainty{certainty: 0.1, speculation: 0.8}
      }

      assert Analysis.compute_sentiment_score(result) < -0.1
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
      score = Analysis.compute_sentiment_score(result)
      assert is_float(score)
    end

    test "loaded_language always reduces score (always pushes negative)" do
      base = %SentimentResult{
        tone: "neutral",
        emotions: %Emotions{},
        rhetoric: %Rhetoric{},
        loaded_language: 0.0,
        certainty: %Certainty{}
      }

      loaded = %{base | loaded_language: 1.0}
      assert Analysis.compute_sentiment_score(loaded) < Analysis.compute_sentiment_score(base)
    end

    test "high speculation relative to certainty reduces score" do
      base = %SentimentResult{
        tone: "neutral",
        emotions: %Emotions{},
        rhetoric: %Rhetoric{},
        loaded_language: 0.0,
        certainty: %Certainty{certainty: 1.0, speculation: 0.0}
      }

      speculative = %{base | certainty: %Certainty{certainty: 0.0, speculation: 1.0}}
      assert Analysis.compute_sentiment_score(speculative) < Analysis.compute_sentiment_score(base)
    end

    test "result is always a float rounded to 4 decimal places" do
      result = %SentimentResult{
        tone: "positive",
        emotions: %Emotions{joy: 0.333},
        rhetoric: %Rhetoric{},
        loaded_language: 0.0,
        certainty: %Certainty{}
      }

      score = Analysis.compute_sentiment_score(result)
      assert is_float(score)
      # No more than 4 decimal places
      assert score == Float.round(score, 4)
    end

    test "alarmist/dismissive/sarcastic rhetoric reduces score vs supportive/analytical" do
      positive_rhetoric = %SentimentResult{
        tone: "neutral",
        emotions: %Emotions{},
        rhetoric: %Rhetoric{supportive: 1.0, analytical: 1.0},
        loaded_language: 0.0,
        certainty: %Certainty{}
      }

      negative_rhetoric = %SentimentResult{
        tone: "neutral",
        emotions: %Emotions{},
        rhetoric: %Rhetoric{alarmist: 1.0, dismissive: 1.0, sarcastic: 1.0},
        loaded_language: 0.0,
        certainty: %Certainty{}
      }

      assert Analysis.compute_sentiment_score(positive_rhetoric) >
               Analysis.compute_sentiment_score(negative_rhetoric)
    end
  end

  # ---------------------------------------------------------------------------
  # classify/1
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

    test "score within [-0.1, 0.1] inclusive is :neutral" do
      assert Analysis.classify(0.0) == :neutral
      assert Analysis.classify(0.1) == :neutral
      assert Analysis.classify(-0.1) == :neutral
    end

    test "just outside threshold boundaries are classified correctly" do
      # Float.round/2 is used on scores, so 0.1001 would remain :positive
      assert Analysis.classify(0.1001) == :positive
      assert Analysis.classify(-0.1001) == :negative
    end
  end

  # ---------------------------------------------------------------------------
  # label/1
  # ---------------------------------------------------------------------------

  describe "label/1" do
    test "returns capitalised string matching CSS class names" do
      assert Analysis.label(0.5) == "Positive"
      assert Analysis.label(-0.5) == "Negative"
      assert Analysis.label(0.0) == "Neutral"
    end

    test "threshold boundary values return Neutral" do
      assert Analysis.label(0.1) == "Neutral"
      assert Analysis.label(-0.1) == "Neutral"
    end

    test "label/1 is consistent with classify/1" do
      for score <- [0.5, -0.5, 0.0, 0.1, -0.1] do
        expected = score |> Analysis.classify() |> Atom.to_string() |> String.capitalize()
        assert Analysis.label(score) == expected
      end
    end
  end
end
