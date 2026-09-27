# General notes about UI/UX
File contains time ordered notes regarding changes and / or ideas of
UI/UX/Design. Version info (as start point of thoughtflow) is optional.
Timestamps are in format DD-MM-YY.

## 24-09-26
Additional / new actions:
 - I want to set / change settings of application (how it should be run), not
   only be able to delete it
 - I want to be more precise on how the new user should be created, whether
   there should be .bashrc initialization / reinitialization due to XDG,
   DBUS and ssh-agent, etc
    - I want to be able to set this even for existing user
    - I want to be able to set cleaning procedure after user removal from
      clientdock so it will turn everything into original order (at least when
      it comes to the aforementioned things added by clientdeck)
 - what if in-between runs someone erases given user or application?
    - clientdesk should check prior to run of application if it exists and
      also on startup, broken apps should have distinctive visuals as well as
      clients whose underlying users does not exists
 - when I call for the application I should get several instances (for example
   5 visual studios)
 - 'No logo' should be represented somehow to avoid void
 - alow set the color of the prompt (user / homedir) or allow PS1 creation...