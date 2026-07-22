# Lista de verificação para envio à App Store (Submission Checklist)

## Projeto e build

- [x] Bundle ID definido como `com.pauloricardo.chronohud`.
- [x] Versão definida como `1.0.0` e build como `1`.
- [x] App Sandbox ativado.
- [x] Hardened Runtime ativado.
- [x] `PrivacyInfo.xcprivacy` declara nenhum rastreamento, nenhum dado coletado e motivo UserDefaults `CA92.1`.
- [x] `ITSAppUsesNonExemptEncryption` definido como `false`.
- [ ] Confirmar que o Bundle ID existe na conta Apple Developer.
- [ ] Selecionar a Equipe (Team) e a identidade de assinatura Mac Distribution corretas.
- [ ] Gerar Archive com a configuração Release em um diretório de build limpo.
- [ ] Validar o archive no Organizer antes de enviar.
- [ ] Executar um teste final de instalação/inicialização a partir da build arquivada.

## App Store Connect

- [ ] Criar o registro do app para macOS com o nome `CHRONO HUD`, idioma principal, Bundle ID e SKU.
- [ ] Adicionar os metadados pt-BR e en-US desta pasta.
- [ ] Confirmar todos os limites de metadados após colar no App Store Connect.
- [ ] Escolher Produtividade como categoria principal e Utilidades como categoria secundária.
- [ ] Preencher o questionário atual de classificação etária com precisão.
- [ ] Selecionar “Não, não coletamos dados” em Privacidade do App.
- [ ] Confirmar que o rastreamento está declarado como não utilizado.
- [ ] Publicar a política de privacidade em uma página HTTPS pública e substituir as URLs temporárias.
- [ ] Publicar uma página de suporte com informações de contato reais e substituir as URLs temporárias.
- [ ] Adicionar nome, e-mail e telefone de contato para a equipe de App Review.
- [ ] Colar as notas de revisão (review notes) e anexar a build enviada.
- [ ] Concluir as configurações de preço, disponibilidade, direitos de conteúdo e lançamento.

## Capturas de tela (Screenshots)

- [ ] Capturar pelo menos uma e até dez capturas de tela macOS por localização.
- [ ] Usar um tamanho aceito de Mac em 16:10, como 1280×800 pixels.
- [ ] Exportar como PNG ou JPEG sem transparência (alpha).
- [ ] Mostrar o HUD normal, modo compacto, log de eventos, configurações e histórico onde for útil.
- [ ] Verificar se as capturas de tela não contêm dados privados, UI de debug, artefatos de cursor ou conteúdo enganoso.

## Revisão final

- [ ] Confirmar que o nome do app e o subtítulo possuem no máximo 30 caracteres cada.
- [ ] Confirmar que o texto promocional possui no máximo 170 caracteres.
- [ ] Confirmar que a descrição possui no máximo 4.000 caracteres.
- [ ] Confirmar que as palavras-chave possuem no máximo 100 bytes UTF-8 e não contêm termos de concorrentes/marcas registradas.
- [ ] Revisar ambas as localizações na prévia da página do produto.
- [ ] Enviar apenas após o App Store Connect informar que não há campos obrigatórios ausentes.
