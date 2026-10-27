unit HelpFrm;

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, StdCtrls, ComCtrls;

type
  THelpTopic = (htKeyboard, htMouse, htTouch, htEffects);

  THelpEntry = record
    Action: string;
    Command: string;
  end;

  // Aide du menu Aide : une liste Action / Commande par sujet, plus une remarque en bas.
  THelpForm = class(TForm)
    lvHelp: TListView;
    lblNote: TLabel;
    btnClose: TButton;
    procedure FormShow(Sender: TObject);
  private
    FTopic: THelpTopic;
  public
    property Topic: THelpTopic read FTopic write FTopic;
  end;

function HelpEntryCount(Topic: THelpTopic): Integer;

implementation

{$R *.dfm}

const
  kHelpTitles: array[THelpTopic] of string = ('Raccourcis clavier', 'Actions de la souris', 'Gestes tactiles',
    'Effets de couleur');

  kKeyboardHelp: array[0..6] of THelpEntry = (
    (Action: 'Zoom avant x2, au centre'; Command: '+'),
    (Action: 'Zoom arrière x2, au centre'; Command: '-'),
    (Action: 'Déplacer d''un dixième de la largeur'; Command: 'Flèches'),
    (Action: 'Vue précédente'; Command: 'Retour arrière'),
    (Action: 'Annuler la sélection en cours'; Command: 'Échap'),
    (Action: 'Plein écran'; Command: 'F11'),
    (Action: 'Retirer le favori sélectionné'; Command: 'Suppr (dans la liste)'));

  kMouseHelp: array[0..4] of THelpEntry = (
    (Action: 'Déplacer l''image'; Command: 'Glisser, bouton gauche'),
    (Action: 'Zoomer sur le point visé'; Command: 'Molette'),
    (Action: 'Zoomer sur une zone (proportions conservées)'; Command: 'Glisser, bouton droit'),
    (Action: 'Choisir le point de l''aperçu Julia'; Command: 'Survol'),
    (Action: 'Ouvrir un favori'; Command: 'Double-clic dans la liste'));

  kTouchHelp: array[0..3] of THelpEntry = (
    (Action: 'Déplacer l''image'; Command: 'Glisser à un ou deux doigts'),
    (Action: 'Zoom avant / arrière'; Command: 'Écarter / pincer deux doigts'),
    (Action: 'Zoomer sur une zone'; Command: 'Appui long, puis glisser'),
    (Action: 'Choisir le point de l''aperçu Julia'; Command: 'Toucher ou glisser à un doigt'));

  kEffectsHelp: array[0..3] of THelpEntry = (
    (Action: 'Colorer par bandes'; Command: 'Effets : mode Bandes (Largeur, Modelé)'),
    (Action: 'Souligner le bord des bandes'; Command: 'Effets : Contours (Épaisseur)'),
    (Action: 'Donner du relief'; Command: 'Effets : Relief (Lumière, Intensité, Hauteur)'),
    (Action: 'Revenir au rendu lisse'; Command: 'Effets : mode Lisse, ou bouton de remise à zéro des effets'));

  kHelpNotes: array[THelpTopic] of string = (
    'Les touches de navigation sont ignorées quand le focus est dans un champ, une liste ou un curseur ' +
      'du panneau latéral.',
    'Le glisser gauche et la molette agissent en mode Libre ; en mode Aperçu Julia, le survol choisit ' +
      'le point. Le glisser droit fonctionne dans les deux modes.',
    'Un doigt seul agit comme la souris (voir Souris) ; les gestes à deux doigts fonctionnent dans les deux ' +
      'modes de navigation (écran tactile, Windows 7 ou plus récent).',
    'Les réglages du panneau Effets recolorent l''image tout de suite, sans recalcul, et sont enregistrés avec ' +
      'les lieux. En mode Bandes, la couleur est constante dans chaque bande (la largeur est une fraction du ' +
      'cycle de la palette) ; le modelé éclaire la bande de son début à son bord. Le relief éclaire l''image ' +
      'comme un paysage dont l''altitude est la position dans la palette : la lumière vient de l''angle ' +
      'choisi, la hauteur amplifie la pente.');

{------------------------------------------------------------------------------}

procedure THelpForm.FormShow(Sender: TObject);

  procedure AddEntries(const Entries: array of THelpEntry);
  var
    I: Integer;
    Item: TListItem;
  begin
    for I := 0 to High(Entries) do
    begin
      Item := lvHelp.Items.Add;
      Item.Caption := Entries[I].Action;
      Item.SubItems.Add(Entries[I].Command);
    end;
  end;

begin
  Caption := 'Aide - ' + kHelpTitles[FTopic];
  lblNote.Caption := kHelpNotes[FTopic];
  lvHelp.Items.BeginUpdate;
  try
    lvHelp.Items.Clear;
    case FTopic of
      htKeyboard:
        AddEntries(kKeyboardHelp);
      htMouse:
        AddEntries(kMouseHelp);
      htTouch:
        AddEntries(kTouchHelp);
      htEffects:
        AddEntries(kEffectsHelp);
    end;
  finally
    lvHelp.Items.EndUpdate;
  end;
end;

{------------------------------------------------------------------------------}

function HelpEntryCount(Topic: THelpTopic): Integer;
begin
  case Topic of
    htKeyboard:
      Result := Length(kKeyboardHelp);
    htMouse:
      Result := Length(kMouseHelp);
    htEffects:
      Result := Length(kEffectsHelp);
  else
    Result := Length(kTouchHelp);
  end;
end;

end.
