defmodule OperationTest do
  use ExUnit.Case, async: true

  defmodule Operation do
    use Exop.Operation

    parameter :param1, type: :integer
    parameter :param2, type: :string

    def process(params) do
      ["This is the process/1 params", params]
    end
  end

  @valid_contract [
    %{name: :param1, opts: [type: :integer]},
    %{name: :param2, opts: [type: :string]}
  ]

  test "defines contract/0" do
    assert :functions |> Operation.__info__ |> Keyword.has_key?(:contract)
  end

  test "stores defined properties in a contract" do
    assert Operation.contract |> is_list
    assert Operation.contract |> List.first |> is_map
    assert Enum.sort(Operation.contract) == Enum.sort(@valid_contract)
  end

  test "defines run/1" do
    assert :functions |> Operation.__info__ |> Keyword.has_key?(:run)
  end

  test "process/1 takes a single param which is Map type" do
    assert Operation.run(param1: 1, param2: "string") == {:ok, ["This is the process/1 params", %{param1: 1, param2: "string"}]}
  end

  test "run/1: returns :validation_failed error when contract didn't pass validation" do
    {:error, {:validation, reasons}} = Operation.run(param1: "not integer", param2: 777)
    assert is_map(reasons)
  end

  test "run/1: pass default value of missed parameter" do
    defmodule DefOperation do
      use Exop.Operation

      parameter :param2, required: false
      parameter :param, default: 999

      def process(params) do
        params[:param]
      end
    end

    assert DefOperation.run == {:ok, 999}
  end

  test "run/1: pass default value of required missed parameter (thus pass a validation)" do
    defmodule Def2Operation do
      use Exop.Operation

      parameter :param, required: true, default: 999

      def process(params) do
        params[:param]
      end
    end

    assert Def2Operation.run() == {:ok, 999}
  end

  test "run/1: doesn't pass default value if a parameter was passed to run/1" do
    defmodule Def3Operation do
      use Exop.Operation

      parameter :param, type: :integer, default: 999

      def process(params) do
        params[:param]
      end
    end

    assert Def3Operation.run(param: 111) == {:ok, 111}
  end

  test "params/1: doesn't invoke a contract validation" do
    assert Operation.process(param1: "not integer", param2: 777) == ["This is the process/1 params", [param1: "not integer", param2: 777]]
  end

  test "defined_params/0: returns params that were defined in the contract, filter out others" do
    defmodule Def4Operation do
      use Exop.Operation

      parameter :a
      parameter :b

      def process(params) do
        params |> defined_params
      end
    end

    assert Def4Operation.run(a: 1, b: 2, c: 3) == {:ok, %{a: 1, b: 2}}
  end

  test "defined_params/0: respects defaults" do
    defmodule Def5Operation do
      use Exop.Operation

      parameter :a
      parameter :b, default: 2

      def process(params) do
        params |> defined_params
      end
    end

    assert Def5Operation.run(a: 1, c: 3) == {:ok, %{a: 1, b: 2}}
  end

  test "run/1: returns the last defined value for duplicated keys" do
    defmodule Def6Operation do
      use Exop.Operation

      parameter :a
      parameter :b

      def process(params), do: params
    end

    assert Def6Operation.run(a: 1, b: 3) == {:ok, %{a: 1, b: 3}}
    assert Def6Operation.run(%{a: 1, b: 3}) == {:ok, %{a: 1, b: 3}}
    assert Def6Operation.run(a: 1, a: 3, b: 2) == {:ok, %{a: 3, b: 2}}
  end

  test "interrupt/1: interupts process and returns the interuption result" do
    defmodule Def7Operation do
      use Exop.Operation
      parameter :x, required: false

      def process(_params) do
        interrupt(%{my_error: "oops"})
        :ok
      end
    end

    assert Def7Operation.run == {:interrupt, %{my_error: "oops"}}
  end

  test "interrupt/1: pass other exceptions" do
    defmodule Def8Operation do
      use Exop.Operation
      parameter :x, required: false

      def process(_params) do
        raise "runtime error"
        interrupt(%{my_error: "oops"})
        :ok
      end
    end

    assert_raise(RuntimeError, fn -> Def8Operation.run end)
  end

  defmodule TruePolicy do
    use Exop.Policy

    def test(_opts), do: true
  end

  defmodule FalsePolicy do
    use Exop.Policy

    def test(_opts), do: false
  end

  defmodule TestUser do
    defstruct [:name, :email]
  end

  test "stores policy module and action" do
    defmodule Def9Operation do
      use Exop.Operation
      policy TruePolicy, :test
      parameter :x, required: false

      def process(_params), do: current_policy()
    end

    assert Def9Operation.run == {:ok, {TruePolicy, :test}}
  end

  test "authorizes with provided policy" do
    defmodule Def10Operation do
      use Exop.Operation
      policy TruePolicy, :test
      parameter :x, required: false

      def process(_params), do: authorize(user: %TestUser{})
    end

    assert Def10Operation.run == {:ok, :ok}

    defmodule Def11Operation do
      use Exop.Operation
      policy FalsePolicy, :test
      parameter :x, required: false

      def process(_params), do: authorize(user: %TestUser{})
    end

    assert Def11Operation.run == {:error, {:auth, :test}}
  end

  test "operation invokation stops if auth failed" do
    defmodule Def12Operation do
      use Exop.Operation
      policy FalsePolicy, :test
      parameter :x, required: false

      def process(_params) do
        authorize %TestUser{}
        :you_will_never_get_here
      end
    end

    assert Def12Operation.run == {:error, {:auth, :test}}
  end

  test "returns errors with malformed policy definition" do
    defmodule Def14Operation do
      use Exop.Operation
      policy UnknownPolicy, :test
      parameter :x, required: false

      def process(_params), do: authorize(%TestUser{})
    end

    defmodule Def15Operation do
      use Exop.Operation
      policy TruePolicy, :unknown_action
      parameter :x, required: false

      def process(_params), do: authorize(%TestUser{})
    end

    assert Def14Operation.run == {:error, {:auth, :unknown_policy}}
    assert Def15Operation.run == {:error, {:auth, :unknown_policy}}
  end

  test "the last policy definition overrides previous definitions" do
    defmodule Def16Operation do
      use Exop.Operation
      policy TruePolicy, :test
      policy FalsePolicy, :test
      parameter :x, required: false

      def process(_params), do: current_policy()
    end

    assert Def16Operation.run == {:ok, {FalsePolicy, :test}}
  end

  test "coerce option changes a parameter value (and after defaults resolving)" do
    defmodule Def17Operation do
      use Exop.Operation

      parameter :a, default: 5, coerce_with: &__MODULE__.coerce/1
      parameter :b

      def process(params), do: {params[:a], params[:b]}

      def coerce(x), do: x * 2
    end

    assert Def17Operation.run(b: 0) == {:ok, {10, 0}}
  end

  test "coerce option changes a parameter value before validation" do
    defmodule Def18Operation do
      use Exop.Operation

      parameter :a, numericality: %{greater_than: 0}, coerce_with: &__MODULE__.coerce/1

      def process(params), do: params[:a]

      def coerce(x), do: x * 2
    end

    defmodule Def19Operation do
      use Exop.Operation

      parameter :a, required: true, coerce_with: &__MODULE__.coerce/1

      def process(params), do: params[:a]

      def coerce(_x), do: "str"
    end

    defmodule Def20Operation do
      use Exop.Operation

      parameter :a, func: &__MODULE__.validate/2, coerce_with: &__MODULE__.coerce/1
      parameter :b, func: &__MODULE__.validate/1

      def process(params), do: params

      def validate(_params, x), do: validate(x)

      def validate(x), do: x > 0

      def coerce(x), do: x + 1
    end

    assert Def18Operation.run(a: 2) == {:ok, 4}
    assert Def18Operation.run(a: 0) == {:error, {:validation, %{a: ["must be greater than 0"]}}}

    assert Def19Operation.run() == {:ok, "str"}

    assert Def20Operation.run(a: -1, b: 0) == {:error, {:validation, %{a: ["isn't valid"], b: ["isn't valid"]}}}
    assert Def20Operation.run(a: 0, b: 0) == {:error, {:validation, %{b: ["isn't valid"]}}}
    assert Def20Operation.run(a: 0, b: 1) == {:ok, %{a: 1, b: 1}}
  end

  test "run!/1: return operation's result with valid params" do
    defmodule Def21Operation do
      use Exop.Operation

      parameter :param, required: true

      def process(params) do
        params[:param] <> " World!"
      end
    end

    assert Def21Operation.run!(param: "Hello") == "Hello World!"
  end

  test "run!/1: return an error with invalid params" do
    defmodule Def22Operation do
      use Exop.Operation

      parameter :param, required: true

      def process(params) do
        params[:param] <> " World!"
      end
    end

    assert_raise Exop.Validation.ValidationError, fn -> Def22Operation.run!() end
  end

  test "run!/1: doesn't affect unhandled errors" do
    defmodule Def23Operation do
      use Exop.Operation

      parameter :param, required: true

      def process(_params), do: raise("oops")
    end

    assert_raise RuntimeError, "oops", fn -> Def23Operation.run!(param: "hi!") end
  end

  test "run!/1: doesn't affect interruptions" do
    defmodule Def24Operation do
      use Exop.Operation

      parameter :param

      def process(_params), do: interrupt()
    end

    assert Def24Operation.run!(param: :a) == {:interrupt, nil}
  end

  test "run/1: returns unwrapped error tuple if process/1 returns it" do
    defmodule Def25Operation do
      use Exop.Operation

      parameter :param

      def process(params) do
        if params[:param], do: params[:param], else: {:error, :ooops}
      end
    end

    assert Def25Operation.run(param: 111) == {:ok, 111}
    assert Def25Operation.run(param: nil) == {:error, :ooops}
  end

  test "run!/1: returns unwrapped error tuple if process/1 returns it" do
    defmodule Def26Operation do
      use Exop.Operation

      parameter :param

      def process(params) do
        if params[:param], do: params[:param], else: {:error, :ooops}
      end
    end

    assert Def26Operation.run!(param: 111) == 111
    assert Def26Operation.run!(param: nil) == {:error, :ooops}
  end

  test "custom validation function takes a contract as the first parameter" do
    defmodule Def27Operation do
      use Exop.Operation

      parameter :a, default: 5
      parameter :b, func: &__MODULE__.custom_validation/2

      def process(params), do: {params[:a], params[:b]}

      def custom_validation(params, b) do
        params[:a] > 10 && b < 10
      end
    end

    assert Def27Operation.run(a: 11, b: 0) == {:ok, {11, 0}}
    assert Def27Operation.run(a: 0, b: 0) == {:error, {:validation, %{b: ["isn't valid"]}}}
  end

  test "run/1: returns unwrapped tuple {:ok, result} if process/1 returns {:ok, result}" do
    defmodule Def28Operation do
      use Exop.Operation

      parameter :param, required: true

      def process(params) do
        {:ok, params[:param]}
      end
    end

    assert Def28Operation.run(param: "hello") == {:ok, "hello"}
  end

  test "list_item + default value" do
    defmodule Def29Operation do
      use Exop.Operation

      parameter :list_param, list_item: %{type: :string, length: %{min: 7}}, default: ["1234567", "7chars"]

      def process(params), do: {:ok, params[:list_param]}
    end

    assert Def29Operation.run() == {:error, {:validation, %{"list_param[1]" => ["length must be greater than or equal to 7"]}}}
  end

  test "list_item + coerce_with" do
    defmodule Def30Operation do
      use Exop.Operation

      parameter :list_param, list_item: [type: :string, length: %{min: 7}], coerce_with: &__MODULE__.make_list/1

      def process(params), do: {:ok, params[:list_param]}

      def make_list(_), do: ["1234567", "7chars"]
    end

    assert Def30Operation.run() == {:error, {:validation, %{"list_param[1]" => ["length must be greater than or equal to 7"]}}}
  end

  test "string-named parameters are allowed" do
    defmodule Def31Operation do
      use Exop.Operation

      parameter "a", type: :string, required: true
      parameter "b", type: :integer, required: true

      def process(params), do: {:ok, params}
    end

    assert Def31Operation.run() == {:error, {:validation, %{"a" => ["is required"], "b" => ["is required"]}}}
    assert Def31Operation.run(%{"a" => 1, "b" => "2"}) == {:error, {:validation, %{"a" => ["has wrong type"], "b" => ["has wrong type"]}}}
    assert Def31Operation.run(%{"a" => "1", b: 2}) == {:error, {:validation, %{"b" => ["is required"]}}}
    assert Def31Operation.run(%{"a" => "1", "b" => 2}) == {:ok, %{"a" => "1", "b" => 2}}
  end

  test "mix-named parameters are allowed" do
    defmodule Def32Operation do
      use Exop.Operation

      parameter "a", type: :string, required: true
      parameter :b, type: :integer, required: true

      def process(params), do: {:ok, params}
    end

    assert Def32Operation.run() == {:error, {:validation, %{"a" => ["is required"], :b => ["is required"]}}}
    assert Def32Operation.run(%{"a" => 1, b: "2"}) == {:error, {:validation, %{"a" => ["has wrong type"], :b => ["has wrong type"]}}}
    assert Def32Operation.run(%{"a" => "1"}) == {:error, {:validation, %{:b => ["is required"]}}}
    assert Def32Operation.run(%{"a" => "1", b: 2}) == {:ok, %{"a" => "1", :b => 2}}
  end

  test "returns any-length error tuple" do
    defmodule Def33Operation do
      use Exop.Operation

      parameter :a, type: :integer, required: true

      def process(%{a: 1}), do: {:error}
      def process(%{a: 2}), do: {:error, 2}
      def process(%{a: 3}), do: {:error, 2, 3}
      def process(%{a: 4}), do: {:error, 2, 3, 4}
      def process(params), do: params
    end

    assert Def33Operation.run() == {:error, {:validation, %{a: ["is required"]}}}
    assert Def33Operation.run(a: 1) == {:error}
    assert Def33Operation.run(a: 2) == {:error, 2}
    assert Def33Operation.run(a: 3) == {:error, 2, 3}
    assert Def33Operation.run(a: 4) == {:error, 2, 3, 4}
    assert Def33Operation.run(a: 777) == {:ok, %{a: 777}}
  end

  test "coerce_with can invoke a function with arity == 2 (passing param_name & param_value)" do
    defmodule Def34Operation do
      use Exop.Operation

      parameter :a, type: :tuple, coerce_with: &__MODULE__.coerce_with_name/2

      def process(params), do: params

      def coerce_with_name(param_name, param_value) do
        {List.duplicate(param_name, 2), param_value * 10}
      end
    end

    assert Def34Operation.run(a: 1.1) == {:ok, %{a: {[:a, :a], 11}}}
  end

  test "coerce_with respects an error-tuple result" do
    defmodule Def35Operation do
      use Exop.Operation

      parameter :a, type: :integer, coerce_with: &__MODULE__.coerce/1

      def process(params), do: params

      def coerce(1), do: {:error, :some_error}
      def coerce(2), do: 2
    end

    assert Def35Operation.run(a: 2) == {:ok, %{a: 2}}
    assert Def35Operation.run(a: 1) == {:error, :some_error}
  end

  describe "allow_nil options" do
    test "allows to have nil as parameter value" do
      defmodule Def36Operation do
        use Exop.Operation

        parameter :a, type: :integer, allow_nil: true, required: false
        parameter :b, type: :integer, allow_nil: false, required: false

        def process(params), do: params
      end

      assert Def36Operation.run(a: 1) == {:ok, %{a: 1}}
      assert Def36Operation.run(a: nil) == {:ok, %{a: nil}}
      assert Def36Operation.run(b: 1) == {:ok, %{b: 1}}
      assert Def36Operation.run(b: nil) == {:error, {:validation, %{b: ["doesn't allow nil", "has wrong type"]}}}
    end

    test "skips all checks" do
      defmodule Def37Operation do
        use Exop.Operation

        parameter :a, type: :integer, numericality: [greater_than: 2], allow_nil: true, required: false
        parameter :b, allow_nil: true, func: &__MODULE__.nil_check/2, required: false

        def nil_check(_, nil), do: {:error, :this_is_nil}

        def process(params), do: params
      end

      assert Def37Operation.run(a: nil) == {:ok, %{a: nil}}
      assert Def37Operation.run(a: 1) == {:error, {:validation, %{a: ["must be greater than 2"]}}}
      assert Def37Operation.run(a: "1") == {:error, {:validation, %{a: ["not a number", "has wrong type"]}}}
      assert Def37Operation.run(b: nil) == {:ok, %{b: nil}}
    end

    test "required: false + allow_nil: false" do
      defmodule Def45Operation do
        use Exop.Operation

        parameter :a, required: false, allow_nil: false

        def process(params), do: params
      end

      assert Def45Operation.run(a: :a) == {:ok, %{a: :a}}
      assert Def45Operation.run() == {:ok, %{}}
      assert Def45Operation.run(a: nil) == {:error, {:validation, %{a: ["doesn't allow nil"]}}}
    end
  end

  describe "when parameter is required" do
    test "all parameters are required by default" do
      defmodule Def38Operation do
        use Exop.Operation

        parameter :a, type: :integer

        def process(params), do: params
      end

      assert Def38Operation.run(a: nil) == {:error, {:validation, %{a: ["has wrong type"]}}}
      assert Def38Operation.run() == {:error, {:validation, %{a: ["is required"]}}}
    end

    test "with allow_nil" do
      defmodule Def39Operation do
        use Exop.Operation, name_in_errors: true

        parameter :a, type: :integer, allow_nil: true

        def process(params), do: params
      end

      assert Def39Operation.run(a: nil) == {:ok, %{a: nil}}
      assert Def39Operation.run() == {:error, {:validation, %{a: ["is required"]}}}
    end

    test "with default" do
      defmodule Def40Operation do
        use Exop.Operation

        parameter :a, type: :integer, default: 7

        def process(params), do: params
      end

      assert Def40Operation.run(a: nil) == {:error, {:validation, %{a: ["has wrong type"]}}}
      assert Def40Operation.run() == {:ok, %{a: 7}}
    end
  end

  describe "when parameter is not required" do
    test "should be not required explicitly" do
      defmodule Def41Operation do
        use Exop.Operation

        parameter :a, type: :integer, required: false

        def process(params), do: params
      end

      assert Def41Operation.run(a: nil) == {:error, {:validation, %{a: ["has wrong type"]}}}
      assert Def41Operation.run() == {:ok, %{}}
    end

    test "with allow_nil" do
      defmodule Def42Operation do
        use Exop.Operation

        parameter :a, type: :integer, required: false, allow_nil: true

        def process(params), do: params
      end

      assert Def42Operation.run(a: nil) == {:ok, %{a: nil}}
      assert Def42Operation.run() == {:ok, %{}}
    end

    test "with default" do
      defmodule Def43Operation do
        use Exop.Operation

        parameter :a, type: :integer, required: false, default: 7

        def process(params), do: params
      end

      assert Def43Operation.run(a: nil) == {:error, {:validation, %{a: ["has wrong type"]}}}
      assert Def43Operation.run() == {:ok, %{a: 7}}
    end
  end

  test ":inner check validates a parameter type" do
    defmodule Def44Operation do
      use Exop.Operation

      parameter :a, inner: %{b: [type: :atom], c: [type: :string]}

      def process(params), do: params
    end

    assert Def44Operation.run(a: :a) == {:error, {:validation, %{a: ["has wrong type"]}}}
    assert Def44Operation.run(a: []) == {:error, {:validation, %{"a[:b]" => ["is required"], "a[:c]" => ["is required"]}}}
    assert Def44Operation.run(a: %{}) == {:error, {:validation, %{"a[:b]" => ["is required"], "a[:c]" => ["is required"]}}}
    assert Def44Operation.run(a: [b: :b, c: "c"]) == {:ok, %{a: [b: :b, c: "c"]}}
    assert Def44Operation.run(a: %{b: :b, c: "c"}) == {:ok, %{a: %{b: :b, c: "c"}}}
  end

  test ":inner check accepts opts as both map and keyword" do
    defmodule Def46Operation do
      use Exop.Operation

      parameter :a, inner: [b: [type: :atom], c: [type: :string]]

      def process(params), do: params
    end

    defmodule Def47Operation do
      use Exop.Operation

      parameter :a, inner: %{b: [type: :atom], c: [type: :string]}

      def process(params), do: params
    end

    assert Def46Operation.run(a: :a) == {:error, {:validation, %{a: ["has wrong type"]}}}
    assert Def46Operation.run(a: []) == {:error, {:validation, %{"a[:b]" => ["is required"], "a[:c]" => ["is required"]}}}
    assert Def46Operation.run(a: %{}) == {:error, {:validation, %{"a[:b]" => ["is required"], "a[:c]" => ["is required"]}}}
    assert Def46Operation.run(a: [b: :b, c: "c"]) == {:ok, %{a: [b: :b, c: "c"]}}
    assert Def46Operation.run(a: %{b: :b, c: "c"}) == {:ok, %{a: %{b: :b, c: "c"}}}

    assert Def47Operation.run(a: :a) == {:error, {:validation, %{a: ["has wrong type"]}}}
    assert Def47Operation.run(a: []) == {:error, {:validation, %{"a[:b]" => ["is required"], "a[:c]" => ["is required"]}}}
    assert Def47Operation.run(a: %{}) == {:error, {:validation, %{"a[:b]" => ["is required"], "a[:c]" => ["is required"]}}}
    assert Def47Operation.run(a: [b: :b, c: "c"]) == {:ok, %{a: [b: :b, c: "c"]}}
    assert Def47Operation.run(a: %{b: :b, c: "c"}) == {:ok, %{a: %{b: :b, c: "c"}}}
  end
end
