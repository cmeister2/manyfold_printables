# frozen_string_literal: true

ManyfoldPrintables::Engine.routes.draw do
  root to: "manyfold_printables/status#index"
  get "link", to: "manyfold_printables/links#new", as: :link
  post "link", to: "manyfold_printables/links#create"
  get "creator_link", to: "manyfold_printables/creator_links#new", as: :creator_link
  post "creator_link", to: "manyfold_printables/creator_links#create"
  patch "settings", to: "manyfold_printables/settings#update", as: :settings
end
