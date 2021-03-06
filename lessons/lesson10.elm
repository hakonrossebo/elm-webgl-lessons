module Main exposing (..)

import Debug
import Keyboard
import Math.Vector2 exposing (Vec2)
import Math.Vector3 exposing (..)
import Math.Matrix4 exposing (..)
import Task exposing (Task, succeed)
import Time exposing (Time)
import WebGL exposing (..)
import Html exposing (Html, text, div)
import Html.App as Html
import AnimationFrame
import Random
import Http
import Array
import String
import Regex
import Html.Attributes exposing (width, height, style)
import List.Extra exposing (getAt, greedyGroupsOf)


effectiveFPMS =
    30.0 / 10000.0


type alias Vertex =
    { position : Vec3, coord : Vec3 }


type alias Model =
    { texture : Maybe Texture
    , keys : Keys
    , position : Vec3
    , facing : Vec3
    , upwardsAngle : Float
    , joggingPhase : Float
    , world : Drawable Vertex
    }


type Action
    = TexturesError Error
    | TexturesLoaded (Maybe Texture)
    | KeyChange (Keys -> Keys)
    | Animate Time
    | FetchFail Http.Error
    | FetchSucceed (Drawable Vertex)


type alias Keys =
    { left : Bool
    , right : Bool
    , up : Bool
    , down : Bool
    , w : Bool
    , s : Bool
    , a : Bool
    , d : Bool
    }


init : ( Model, Cmd Action )
init =
    ( { texture = Nothing
      , position = vec3 0 0.5 1
      , facing = vec3 0 0 -1
      , joggingPhase = 0
      , upwardsAngle = 0
      , keys = Keys False False False False False False False False
      , world = Triangle []
      }
    , Cmd.batch
        [ fetchTexture |> Task.perform TexturesError TexturesLoaded
        , fetchWorld
        ]
    )


fetchWorld : Cmd Action
fetchWorld =
    let
        uri =
            "meshes/world10.txt"
    in
        Task.perform FetchFail FetchSucceed (Http.getString uri `Task.andThen` decodeWorld)


match : List String -> List (List Regex.Match)
match lines =
    List.map (\x -> Regex.find Regex.All (Regex.regex "-?\\d+\\.\\d+") x) lines


filter5 : List (List a) -> List (List a)
filter5 lines =
    List.filter (\x -> 5 == List.length x) lines


toFloatSure : String -> Float
toFloatSure str =
    case String.toFloat str of
        Ok num ->
            num

        Err _ ->
            0.0


extractMatches : List (List Regex.Match) -> List (List Float)
extractMatches matches =
    List.map (\lineMatch -> List.map (toFloatSure << .match) lineMatch) matches


makeTriangle :
    List (List Float)
    -> ( Vertex, Vertex, Vertex )
makeTriangle vertexes =
    case vertexes of
        a :: b :: c :: [] ->
            ( makeVertex a, makeVertex b, makeVertex c )

        _ ->
            ( Vertex (vec3 0 0 0) (vec3 0 0 1)
            , Vertex (vec3 0 0 0) (vec3 0 0 1)
            , Vertex (vec3 0 0 0) (vec3 0 0 1)
            )


makeVertex : List Float -> Vertex
makeVertex coords =
    case coords of
        a :: b :: c :: d :: e :: [] ->
            { position = vec3 a b c, coord = vec3 d e 0 }

        _ ->
            { position = vec3 0 0 0, coord = vec3 0 0 0 }


decodeWorld : String -> Task Http.Error (Drawable Vertex)
decodeWorld source =
    succeed (Triangle (List.map makeTriangle (greedyGroupsOf 3 (extractMatches (filter5 (match (String.lines source)))))))


fetchTexture : Task Error (Maybe Texture)
fetchTexture =
    loadTextureWithFilter WebGL.Linear "textures/crate.gif"
        `Task.andThen`
            \linearTexture ->
                Task.succeed (Just linearTexture)


update : Action -> Model -> ( Model, Cmd Action )
update action model =
    case action of
        FetchFail err ->
            ( model, Cmd.none )

        FetchSucceed world ->
            ( { model | world = world }, Cmd.none )

        TexturesError err ->
            ( model, Cmd.none )

        TexturesLoaded texture ->
            ( { model | texture = texture }, Cmd.none )

        KeyChange keyfunc ->
            ( { model | keys = keyfunc model.keys }, Cmd.none )

        Animate dt ->
            ( { model
                | position =
                    model.position
                        |> move (dt / 500) model.keys model.facing model.joggingPhase
                , facing =
                    model.facing
                        |> rotateY dt model.keys
                , upwardsAngle =
                    model.upwardsAngle
                        |> rotateX dt model.keys
                , joggingPhase =
                    model.joggingPhase
                        |> updateJoggingPhase dt model.keys
              }
            , Cmd.none
            )


updateJoggingPhase : Float -> { keys | a : Bool, s : Bool, w : Bool, d : Bool } -> Float -> Float
updateJoggingPhase dt k phase =
    case ( k.a, k.s, k.d, k.w ) of
        ( False, False, False, False ) ->
            phase

        ( True, True, True, True ) ->
            phase

        ( True, True, False, False ) ->
            phase

        ( False, False, True, True ) ->
            phase

        _ ->
            phase + dt / 100


rotateX : Float -> { keys | up : Bool, down : Bool } -> Float -> Float
rotateX dt k upwardsAngle =
    let
        direction =
            case ( k.up, k.down ) of
                ( True, False ) ->
                    1

                ( False, True ) ->
                    -1

                _ ->
                    0
    in
        addWithCap 89 -89 upwardsAngle (direction * dt / 10)


addWithCap : Float -> Float -> Float -> Float -> Float
addWithCap max min value toAdd =
    if value >= max && toAdd > 0 then
        max
    else if value <= min && toAdd < 0 then
        min
    else
        value + toAdd


rotateY : Float -> { keys | left : Bool, right : Bool } -> Vec3 -> Vec3
rotateY dt k facing =
    let
        direction =
            case ( k.left, k.right ) of
                ( True, False ) ->
                    1

                ( False, True ) ->
                    -1

                _ ->
                    0
    in
        transform (makeRotate (direction * dt / 1000) j) facing


move : Float -> { keys | w : Bool, s : Bool, a : Bool, d : Bool } -> Vec3 -> Float -> Vec3 -> Vec3
move dt k facing joggingPhase position =
    let
        forward =
            case ( k.w, k.s ) of
                ( True, False ) ->
                    1 * dt

                ( False, True ) ->
                    -1 * dt

                _ ->
                    0

        strafe =
            case ( k.a, k.d ) of
                ( True, False ) ->
                    -1 * dt

                ( False, True ) ->
                    1 * dt

                _ ->
                    0
    in
        setY (0.5 + (sin joggingPhase) * 0.05) (position `add` (Math.Vector3.scale strafe (facing `cross` j)) `add` (Math.Vector3.scale forward facing))


main : Program Never
main =
    Html.program
        { init = init
        , view = view
        , subscriptions = subscriptions
        , update = update
        }


subscriptions : Model -> Sub Action
subscriptions _ =
    [ AnimationFrame.diffs Animate
    , Keyboard.downs (keyChange True)
    , Keyboard.ups (keyChange False)
    ]
        |> Sub.batch


keyChange : Bool -> Keyboard.KeyCode -> Action
keyChange on keyCode =
    (case keyCode of
        38 ->
            \k -> { k | up = on }

        40 ->
            \k -> { k | down = on }

        39 ->
            \k -> { k | right = on }

        37 ->
            \k -> { k | left = on }

        87 ->
            \k -> { k | w = on }

        83 ->
            \k -> { k | s = on }

        65 ->
            \k -> { k | a = on }

        68 ->
            \k -> { k | d = on }

        _ ->
            Basics.identity
    )
        |> KeyChange



-- VIEW


view : Model -> Html Action
view { texture, world, position, facing, upwardsAngle } =
    div
        []
        [ WebGL.toHtml
            [ width 500, height 500, style [ ( "backgroundColor", "black" ) ] ]
            (renderEntity world texture position facing upwardsAngle)
        , div
            [ style
                [ ( "font-family", "monospace" )
                , ( "left", "20px" )
                , ( "right", "20px" )
                , ( "top", "500px" )
                ]
            ]
            [ text message ]
        ]


message : String
message =
    "Up/Down/Left/Right turn head, w/a/s/d -> move around"


renderEntity : Drawable { position : Vec3, coord : Vec3 } -> Maybe Texture -> Vec3 -> Vec3 -> Float -> List Renderable
renderEntity world texture position facing upwardsAngle =
    case texture of
        Nothing ->
            []

        Just tex ->
            [ render vertexShader fragmentShader world (uniforms tex position facing upwardsAngle) ]


uniforms : Texture -> Vec3 -> Vec3 -> Float -> { texture : Texture, perspective : Mat4, camera : Mat4, worldSpace : Mat4 }
uniforms texture position facing upwardsAngle =
    { texture = texture
    , worldSpace = makeTranslate (vec3 0 0 0)
    , camera = makeLookAt position (position `add` (transform (makeRotate (degrees upwardsAngle) (facing `cross` j)) facing)) j
    , perspective = makePerspective 45 1 0.01 100
    }



-- SHADERS


vertexShader : Shader { attr | position : Vec3, coord : Vec3 } { unif | worldSpace : Mat4, perspective : Mat4, camera : Mat4 } { vcoord : Vec2 }
vertexShader =
    [glsl|

  precision mediump float;
  attribute vec3 position;
  attribute vec3 coord;
  uniform mat4 worldSpace;
  uniform mat4 perspective;
  uniform mat4 camera;
  varying vec2 vcoord;

  void main() {
    gl_Position = perspective * camera * worldSpace * vec4(position, 1.0);
    vcoord = coord.xy;
  }
|]


fragmentShader : Shader {} { unif | texture : Texture } { vcoord : Vec2 }
fragmentShader =
    [glsl|
  precision mediump float;
  uniform sampler2D texture;
  varying vec2 vcoord;

  void main () {
      gl_FragColor = texture2D(texture, vcoord);
  }

|]
