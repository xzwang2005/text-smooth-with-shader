#include "stdafx.h"
#include "DiscretePathRenderer.h"
#include "Entity3D.h"
#include "Scene.h"
#include "Texture2dConfigDX11.h"
#include "Log.h"
#include "IParameterManager.h"
#include "PipelineManagerDX11.h"
#include "Texture2dDX11.h"
#include "BoundsVisualizerActor.h"
#include "SceneGraph.h"

using namespace Glyph3;

DiscretePathRenderer::DiscretePathRenderer(RendererDX11& Renderer)
: m_Renderer(Renderer)
{
	ViewMatrix.MakeIdentity();
	ProjMatrix.MakeIdentity();
}


DiscretePathRenderer::~DiscretePathRenderer()
{
}


void DiscretePathRenderer::SetTargets(std::vector<ResourcePtr>& renderTargets, ResourcePtr DepthTarget,
	int Viewport)
{
	m_renderTargets = renderTargets;
	SetViewPort(Viewport);
	m_DepthTarget = DepthTarget;
}

void DiscretePathRenderer::Update(float fTime)
{
}
//--------------------------------------------------------------------------------
void DiscretePathRenderer::QueuePreTasks(RendererDX11* pRenderer)
{
	if (m_pEntity != NULL)
	{
		Matrix4f view = m_pEntity->Transform.GetView();
		SetViewMatrix(view);
	}

	// Queue this view into the renderer for processing.
	pRenderer->QueueTask(this);

	if (m_pScene)
	{
		// Run through the graph and pre-render the entities
		m_pScene->PreRender(pRenderer, VT_PERSPECTIVE);
	}
}

void DiscretePathRenderer::ExecuteTask(PipelineManagerDX11* pPipelineManager, IParameterManager* pParamManager)
{
	if (m_pScene)
	{
		// Set the parameters for rendering this view
		pPipelineManager->ClearRenderTargets();
		for (unsigned int i = 0; i < m_renderTargets.size(); ++i)
			pPipelineManager->OutputMergerStage.DesiredState.RenderTargetViews.SetState(i, m_renderTargets[i]->m_iResourceRTV);
		pPipelineManager->OutputMergerStage.DesiredState.DepthTargetViews.SetState(m_DepthTarget->m_iResourceDSV);
		pPipelineManager->ApplyRenderTargets();

		pPipelineManager->ClearBuffers(m_vColor, 1.0f);

		// Configure the desired viewports in this pipeline
		ConfigureViewports(pPipelineManager);

		// Set this view's render parameters
		SetRenderParams(pParamManager);

		// Run through the graph and render each of the entities
		m_pScene->GetRoot()->Render(pPipelineManager, pParamManager, VT_PERSPECTIVE);
	}
}

void DiscretePathRenderer::Resize(UINT width, UINT height)
{
}


std::wstring DiscretePathRenderer::GetName()
{
	return(L"DiscretePathRenderer");
}

void DiscretePathRenderer::SetRenderParams(IParameterManager* pParamManager)
{
	pParamManager->SetViewMatrixParameter(&ViewMatrix);
	pParamManager->SetProjMatrixParameter(&ProjMatrix);
}