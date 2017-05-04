defmodule EHealth.Bamboo.Emails.EmployeeRequestInvitation do
  @moduledoc false

  use Confex, otp_app: :ehealth
  import Bamboo.Email
  alias EHealth.Bamboo.Mailer

  def send(to, body) do
    new_email
    |> to(to)
    |> from(config()[:from])
    |> subject(config()[:subject])
    |> html_body(body)
    |> Mailer.deliver_now()
  end
end
