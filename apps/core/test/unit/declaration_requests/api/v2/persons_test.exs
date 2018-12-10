defmodule Core.DeclarationRequests.API.V2.PersonsTest do
  @moduledoc false

  use Core.ConnCase, async: true
  alias Core.DeclarationRequests.API.V2.Persons

  describe "v2 child search params" do
    test "tax_id" do
      assert {:ok,
              [
                %{
                  "birth_date" => "2018-12-10",
                  "status" => "active",
                  "tax_id" => "0123456789"
                },
                %{
                  "birth_date" => "2018-12-10",
                  "digits" => "2511511",
                  "last_name" => "нечуйлевицький",
                  "status" => "active",
                  "type" => "BIRTH_CERTIFICATE"
                }
              ]} ==
               Persons.get_search_params(%{
                 "tax_id" => "0123456789",
                 "birth_date" => "2018-12-10",
                 "last_name" => "Нечуй Левицький",
                 "documents" => [
                   %{
                     "type" => "BIRTH_CERTIFICATE",
                     "number" => "Стеблівським РОУ МВУ в Черкаській обл. НОМЕР 2511 в 5/11"
                   }
                 ]
               })
    end

    test "no tax_id" do
      assert {:ok,
              [
                %{
                  "birth_date" => "2018-12-10",
                  "digits" => "2511511",
                  "last_name" => "нечуйлевицький",
                  "status" => "active",
                  "type" => "BIRTH_CERTIFICATE"
                }
              ]} ==
               Persons.get_search_params(%{
                 "birth_date" => "2018-12-10",
                 "last_name" => "Нечуй Левицький",
                 "documents" => [
                   %{
                     "type" => "BIRTH_CERTIFICATE",
                     "number" => "Стеблівським РОУ МВУ в Черкаській обл. НОМЕР 2511 в 5/11"
                   }
                 ]
               })
    end
  end

  describe "v2 adult search params" do
    test "tax_id" do
      assert {:ok,
              [
                %{
                  "birth_date" => "1838-11-25",
                  "status" => "active",
                  "tax_id" => "0123456789"
                }
              ]} ==
               Persons.get_search_params(%{
                 "tax_id" => "0123456789",
                 "birth_date" => "1838-11-25",
                 "last_name" => "Нечуй Левицький",
                 "documents" => [
                   %{
                     "type" => "BIRTH_CERTIFICATE",
                     "number" => "Стеблівським РОУ МВУ в Черкаській обл. НОМЕР 2511 в 5/11"
                   }
                 ]
               })
    end

    test "no tax_id" do
      assert {:ok,
              [
                %{
                  "documents" => [
                    %{
                      "number" => "steblivskym rou mvu v cherkaskii obl. nomer 2511 v 5/11",
                      "status" => "active",
                      "type" => "BIRTH_CERTIFICATE"
                    },
                    %{
                      "number" => "18381125-01234",
                      "status" => "active",
                      "type" => "PASSPORT"
                    }
                  ],
                  "status" => "active"
                }
              ]} ==
               Persons.get_search_params(%{
                 "birth_date" => "1838-11-25",
                 "last_name" => "Нечуй Левицький",
                 "documents" => [
                   %{
                     "type" => "BIRTH_CERTIFICATE",
                     "number" => "Стеблівським РОУ МВУ в Черкаській обл. НОМЕР 2511 в 5/11"
                   },
                   %{
                     "type" => "PASSPORT",
                     "number" => "18381125-01234"
                   }
                 ]
               })
    end
  end
end
