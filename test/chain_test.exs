defmodule ChainTest do
  use ExUnit.Case, async: false

  defmodule Sum do
    use Exop.Operation

    parameter :a, type: :integer
    parameter :b, type: :integer

    def process(%{a: a, b: b}) do
      result = a + b
      _next_params = [a: result]
    end
  end

  defmodule MultiplyByHundred do
    use Exop.Operation

    parameter :a, type: :integer
    parameter :additional, type: :integer, required: false

    def process(%{a: a, additional: additional}) do
      result = a * 100 * additional
      _next_params = [a: result]
    end

    def process(%{a: a}) do
      result = a * 100
      _next_params = [a: result]
    end
  end

  defmodule DivisionByTen do
    use Exop.Operation

    parameter :a, type: :integer

    def process(params) do
      _chain_result = params[:a] / 10
    end
  end

  defmodule Fail do
    use Exop.Operation

    parameter :a, type: :string

    def process(_params), do: 1000
  end

  defmodule TestFallback do
    use Exop.Fallback

    def process(_operation, _params, _error), do: "fallback!"
  end

  defmodule WithFallback do
    use Exop.Operation

    fallback TestFallback, return: true

    parameter :a, type: :string

    def process(_params), do: 1000
  end

  defmodule TestChainSuccess do
    use Exop.Chain

    operation Sum
    operation MultiplyByHundred
    operation DivisionByTen
  end

  defmodule TestChainFail do
    use Exop.Chain

    operation Sum
    operation Fail
    operation DivisionByTen
  end

  defmodule TestChainFallback do
    use Exop.Chain

    operation Sum
    operation WithFallback
    operation DivisionByTen
  end

  test "invokes defined operations one by one and return the last result" do
    initial_params = [a: 1, b: 2]
    result = TestChainSuccess.run(initial_params)

    assert {:ok, 30.0} = result
  end

  test "invokes defined operations one by one and return the first not-ok-tuple-result" do
    initial_params = [a: 1, b: 2]
    result = TestChainFail.run(initial_params)

    assert {:error, {:validation, %{a: ["has wrong type"]}}} = result
  end

  test "invokes a fallback module of a failed operation" do
    initial_params = [a: 1, b: 2]
    result = TestChainFallback.run(initial_params)

    assert result == "fallback!"
  end

  defmodule TestChainAdditionalParams do
    use Exop.Chain

    operation Sum
    operation MultiplyByHundred, additional: 2
    operation DivisionByTen
  end

  defmodule TestChainAdditionalParamsFunc do
    use Exop.Chain

    operation Sum
    operation MultiplyByHundred, additional: &__MODULE__.additional/0
    operation DivisionByTen

    def additional, do: 3
  end

  describe "with additional params" do
    test "allows to specify additional params" do
      initial_params = [a: 1, b: 2]
      result = TestChainAdditionalParams.run(initial_params)

      assert {:ok, 60.0} = result
    end

    test "allows to specify additional params as a 0-arity func" do
      initial_params = [a: 1, b: 2]
      result = TestChainAdditionalParamsFunc.run(initial_params)

      assert {:ok, 90.0} = result
    end
  end

  defmodule TestChainFailOpname do
    use Exop.Chain, name_in_error: true

    operation Sum
    operation Fail
    operation DivisionByTen
  end

  defmodule TestChainFallbackOpname do
    use Exop.Chain, name_in_error: true

    operation Sum
    operation WithFallback
    operation DivisionByTen
  end

  describe "with operation name in error output" do
    test "returns failed operation name" do
      initial_params = [a: 1, b: 2]
      result = TestChainFailOpname.run(initial_params)
      assert {ChainTest.Fail, {:error, {:validation, %{a: ["has wrong type"]}}}} = result
    end

    test "doesn't affect an operation with a fallback" do
      initial_params = [a: 1, b: 2]
      result = TestChainFallbackOpname.run(initial_params)
      assert result == "fallback!"
    end
  end

  defmodule TestChainSuccessSteps do
    use Exop.Chain

    step Sum
    step MultiplyByHundred
    step DivisionByTen
  end

  test "step/2 is an alias for operation/2" do
    initial_params = [a: 1, b: 2]
    result = TestChainSuccessSteps.run(initial_params)

    assert {:ok, 30.0} = result
  end
end
